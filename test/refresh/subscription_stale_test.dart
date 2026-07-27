import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/refresh/data_refresh_bus.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/mentors/ui/mentor_detail_screen.dart';

/// §4-1·§4-2 — 구독 상태 세대(DataRefreshBus.subscriptionGeneration)와
/// 멘토 상세의 최신성 수렴(앱 복귀 resume · 세대 신호 · 늦은 응답 폐기).
///
/// 구독은 앱 밖(웹)에서 일어난다(Commerce-Zero — 앱 내 결제·구독 진입 없음).
/// 여기서 검증하는 것은 "앱으로 돌아왔을 때 CTA 가 stale 하지 않다" 뿐이며,
/// 앱 내 결제·구독 실행 경로를 만들지 않는다.

const MentorListItem _mentor = MentorListItem(id: 'm1', nickname: '멘토A');

Widget _app(Future<MentorDetailExtras> Function() loader) => MaterialApp(
      home: MentorDetailScreen(item: _mentor, extrasLoaderOverride: loader),
    );

/// 위젯 테스트 기본 화면이 좁아 오버플로가 나는 것을 막는다(기존 테스트 관행).
void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('§4-1 DataRefreshBus.subscriptionGeneration', () {
    test('bumpSubscription 은 세대 증가 + 리스너 통지(값 미탑재 — 재조회는 각 표면 몫)', () {
      final int start = DataRefreshBus.subscriptionGeneration.value;
      int notified = 0;
      void l() => notified++;
      DataRefreshBus.subscriptionGeneration.addListener(l);
      DataRefreshBus.bumpSubscription();
      expect(DataRefreshBus.subscriptionGeneration.value, start + 1);
      expect(notified, 1);
      DataRefreshBus.subscriptionGeneration.removeListener(l);
    });

    test('지갑 세대와 독립(구독 신호가 지갑 세대를 올리지 않는다)', () {
      final int wallet = DataRefreshBus.walletGeneration.value;
      DataRefreshBus.bumpSubscription();
      expect(DataRefreshBus.walletGeneration.value, wallet);
    });
  });

  group('§4-2 멘토 상세 — 구독 상태 재조회', () {
    testWidgets('앱 복귀(resumed) → 재조회로 CTA 가 최신 구독 상태를 반영한다',
        (WidgetTester tester) async {
      _bigSurface(tester);
      int calls = 0;
      bool subscribed = false;
      await tester.pumpWidget(_app(() async {
        calls++;
        return MentorDetailExtras(alreadySubscribed: subscribed);
      }));
      await tester.pumpAndSettle();
      expect(calls, 1);
      // 비구독: 커머스 안내(비상호작용) — '질문방으로' CTA 없음.
      expect(find.text('질문방으로'), findsNothing);

      // 웹에서 구독 완료 후 앱 복귀.
      subscribed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 2, reason: '무한 새로고침·중복 호출 없음');
      expect(find.text('질문방으로'), findsOneWidget);
    });

    testWidgets('bumpSubscription → 재조회 정확히 1회 + CTA 갱신',
        (WidgetTester tester) async {
      _bigSurface(tester);
      int calls = 0;
      bool subscribed = false;
      await tester.pumpWidget(_app(() async {
        calls++;
        return MentorDetailExtras(alreadySubscribed: subscribed);
      }));
      await tester.pumpAndSettle();
      expect(calls, 1);

      subscribed = true;
      DataRefreshBus.bumpSubscription();
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('질문방으로'), findsOneWidget);
    });

    testWidgets('늦은 이전 응답이 최신 구독 상태를 덮지 않는다(세대 guard)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final Completer<MentorDetailExtras> slow =
          Completer<MentorDetailExtras>();
      int calls = 0;
      await tester.pumpWidget(_app(() {
        calls++;
        // 1회차(구독 '전' 스냅샷)는 늦게 도착, 2회차(구독 후)는 즉시 완료.
        if (calls == 1) return slow.future;
        return Future<MentorDetailExtras>.value(
            const MentorDetailExtras(alreadySubscribed: true));
      }));
      await tester.pump();

      DataRefreshBus.bumpSubscription(); // 최신 조회 시작(빠르게 완료)
      await tester.pumpAndSettle();
      expect(find.text('질문방으로'), findsOneWidget);

      // 구독 '전' 값이 뒤늦게 도착 — 최신 CTA 를 되돌리면 안 된다.
      slow.complete(const MentorDetailExtras(alreadySubscribed: false));
      await tester.pumpAndSettle();
      expect(find.text('질문방으로'), findsOneWidget, reason: 'stale 미반영');
    });

    testWidgets('재조회 중에는 직전 구독 상태를 유지한다(CTA 미확정 깜빡임 0)',
        (WidgetTester tester) async {
      _bigSurface(tester);
      final Completer<MentorDetailExtras> pending =
          Completer<MentorDetailExtras>();
      int calls = 0;
      await tester.pumpWidget(_app(() {
        calls++;
        if (calls == 1) {
          return Future<MentorDetailExtras>.value(
              const MentorDetailExtras(alreadySubscribed: true));
        }
        return pending.future; // 두 번째 재조회는 계속 진행 중
      }));
      await tester.pumpAndSettle();
      expect(find.text('질문방으로'), findsOneWidget);

      // 재조회 시작 — 응답 전이라도 CTA 가 미확정으로 돌아가면 안 된다.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('질문방으로'), findsOneWidget, reason: '재조회 중 직전 값 유지');

      pending.complete(const MentorDetailExtras(alreadySubscribed: true));
      await tester.pumpAndSettle();
    });

    testWidgets('재조회 실패 → 마지막 정상 구독 상태를 지우지 않는다', (WidgetTester tester) async {
      _bigSurface(tester);
      int calls = 0;
      await tester.pumpWidget(_app(() {
        calls++;
        if (calls == 1) {
          return Future<MentorDetailExtras>.value(
              const MentorDetailExtras(alreadySubscribed: true));
        }
        return Future<MentorDetailExtras>.error(StateError('network'));
      }));
      await tester.pumpAndSettle();
      expect(find.text('질문방으로'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('질문방으로'), findsOneWidget, reason: '마지막 정상 스냅샷 보존');
    });

    testWidgets('dispose 후 bump → 재조회·상태 변경·크래시 없음',
        (WidgetTester tester) async {
      _bigSurface(tester);
      int calls = 0;
      await tester.pumpWidget(_app(() async {
        calls++;
        return const MentorDetailExtras();
      }));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final int before = calls;
      DataRefreshBus.bumpSubscription();
      await tester.pump();
      expect(calls, before, reason: 'dispose 후 리스너 해제');
    });
  });
}
