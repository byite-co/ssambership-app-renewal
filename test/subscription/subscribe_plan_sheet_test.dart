import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/core/refresh/data_refresh_bus.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/subscription/data/subscription_commerce_messages.dart';
import 'package:ssambership_app/features/subscription/ui/subscribe_entry_section.dart';
import 'package:ssambership_app/shared/ids/uuid_v4.dart';

import '../support/app_scope_test_harness.dart';
import 'fake_subscription_commerce.dart';

MentorListItem _mentor({List<MentorPlan>? plans}) => MentorListItem(
      id: 'm1',
      nickname: '김멘토',
      plans: plans ??
          const <MentorPlan>[
            MentorPlan(planTier: 'premium', amountCents: 17490000),
            MentorPlan(planTier: 'limited', amountCents: 2990000),
            MentorPlan(planTier: 'standard', amountCents: 8490000),
          ],
    );

Future<void> _pumpEntry(
  WidgetTester tester,
  FakeSubscriptionCommerce port, {
  bool gate = false,
  AppRole role = AppRole.student,
  String Function()? keyFactory,
  MentorListItem? mentor,
  VoidCallback? onAlreadySubscribed,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpScopedWidget(MaterialApp(
    home: Scaffold(
      body: SubscribeEntrySection(
        mentor: mentor ?? _mentor(),
        port: port,
        identityGateOverride: gate,
        roleOverride: role,
        idempotencyKeyFactory: keyFactory,
        onAlreadySubscribed: onAlreadySubscribed,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('구독 결제 시트', () {
    testWidgets('요금제 3구간 · 실제 단가 · 스탠다드 기본 선택 · 잔액 요약', (tester) async {
      final FakeSubscriptionCommerce port =
          FakeSubscriptionCommerce(balanceCents: 4570000);
      await _pumpEntry(tester, port);
      expect(find.text('월 29,900원부터 · 요금제 3가지'), findsOneWidget);
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();

      expect(find.text('요금제를 골라주세요'), findsOneWidget);
      expect(find.text('라이트'), findsOneWidget);
      expect(find.text('스탠다드'), findsOneWidget);
      expect(find.text('프리미엄'), findsOneWidget);
      expect(find.text('주 4문항'), findsOneWidget);
      expect(find.text('주 9문항'), findsOneWidget);
      expect(find.text('질문 무제한'), findsOneWidget);
      expect(find.text('29,900원'), findsOneWidget);
      expect(find.text('174,900원'), findsOneWidget);
      expect(find.text('추천'), findsOneWidget);
      // 요약: 내 캐시 45,700 · 결제 84,900 · 남는 -39,200(위험색) · 부족 문구.
      expect(find.text('45,700원'), findsOneWidget);
      expect(find.text('-39,200원'), findsOneWidget);
      expect(find.text('잔액이 39,200원 부족해요'), findsOneWidget);
      // 부족 → 비활성. 충전 유도 0.
      final FilledButton btn = tester.widget(find.widgetWithText(FilledButton, '84,900원으로 구독하기'));
      expect(btn.onPressed, isNull);
      expect(find.textContaining('충전'), findsNothing);
      expect(find.textContaining('웹'), findsNothing);
      expect(port.subscribeCalls, isEmpty);
      // 라이트로 바꾸면 잔액이 충분해 활성.
      await tester.tap(find.text('라이트'));
      await tester.pumpAndSettle();
      expect(find.text('잔액이 39,200원 부족해요'), findsNothing);
      expect(find.text('15,800원'), findsOneWidget); // 남는 캐시.
      final FilledButton btn2 = tester.widget(find.widgetWithText(FilledButton, '29,900원으로 구독하기'));
      expect(btn2.onPressed, isNotNull);
    });

    testWidgets('성공 → subscribe 1회 · 멱등 키 uuid · 세대 신호 · 방으로 이동 안내', (tester) async {
      final FakeSubscriptionCommerce port =
          FakeSubscriptionCommerce(balanceCents: 10000000);
      final int subGen = DataRefreshBus.subscriptionGeneration.value;
      final int walletGen = DataRefreshBus.walletGeneration.value;
      final int roomsGen = DataRefreshBus.questionRoomsGeneration.value;
      await _pumpEntry(tester, port);
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('84,900원으로 구독하기'));
      await tester.pumpAndSettle();

      expect(port.subscribeCalls, hasLength(1));
      expect(port.subscribeCalls.single['mentorId'], 'm1');
      expect(port.subscribeCalls.single['tier'], 'standard');
      final String key = port.subscribeCalls.single['key']!;
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(key), isTrue,
          reason: 'uuid v4 형식: $key');
      expect(DataRefreshBus.subscriptionGeneration.value, subGen + 1);
      expect(DataRefreshBus.walletGeneration.value, walletGen + 1);
      expect(DataRefreshBus.questionRoomsGeneration.value, roomsGen + 1);
      expect(find.text('구독을 시작했어요. 질문방으로 이동할게요.'), findsOneWidget);
      expect(find.text('요금제를 골라주세요'), findsNothing);
    });

    testWidgets('이중 탭 방지 — 요청 중 버튼 잠금 · 호출 1회', (tester) async {
      final FakeSubscriptionCommerce port =
          FakeSubscriptionCommerce(balanceCents: 10000000)
            ..subscribeGate = Completer<void>();
      await _pumpEntry(tester, port);
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('84,900원으로 구독하기'));
      await tester.pump();
      expect(find.text('결제 중…'), findsOneWidget);
      final FilledButton btn = tester.widget(find.widgetWithText(FilledButton, '결제 중…'));
      expect(btn.onPressed, isNull);
      await tester.tap(find.text('결제 중…'), warnIfMissed: false);
      await tester.pump();
      expect(port.subscribeCalls, hasLength(1));
      port.subscribeGate!.complete();
      await tester.pumpAndSettle();
      expect(port.subscribeCalls, hasLength(1));
    });

    testWidgets('실패 후 재시도는 같은 키 · 요금제 변경은 새 키', (tester) async {
      int n = 0;
      final FakeSubscriptionCommerce port =
          FakeSubscriptionCommerce(balanceCents: 100000000)
            ..subscribeThrow = StateError('network');
      await _pumpEntry(tester, port, keyFactory: () => 'key-${++n}');
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('84,900원으로 구독하기'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('subscribe-error')), findsOneWidget);
      await tester.tap(find.text('84,900원으로 구독하기'));
      await tester.pumpAndSettle();
      expect(port.subscribeCalls.map((c) => c['key']), <String>['key-1', 'key-1']);
      await tester.tap(find.text('프리미엄'));
      await tester.pumpAndSettle();
      port.subscribeThrow = null;
      await tester.tap(find.text('174,900원으로 구독하기'));
      await tester.pumpAndSettle();
      expect(port.subscribeCalls.last['key'], 'key-2');
      expect(port.subscribeCalls.last['tier'], 'premium');
    });

    testWidgets('서버 CASH_INSUFFICIENT → 부족액 문구 · 잔액 갱신 · 충전 유도 0', (tester) async {
      final FakeSubscriptionCommerce port =
          FakeSubscriptionCommerce(balanceCents: 10000000)
            ..subscribeFailCode = 'CASH_INSUFFICIENT'
            ..subscribeFailBody = <String, dynamic>{
              'required_cents': 8490000,
              'balance_cents': 1000000,
              'shortfall_cents': 7490000,
            };
      await _pumpEntry(tester, port);
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('84,900원으로 구독하기'));
      await tester.pumpAndSettle();
      expect(find.text('잔액이 74,900원 부족해요'), findsNWidgets(2)); // 서버 문구 + 요약 부족줄.
      expect(find.text('10,000원'), findsOneWidget); // 서버가 알려준 잔액으로 갱신.
      expect(find.textContaining('충전'), findsNothing);
    });

    testWidgets('오류 코드 6종 매핑 — 정원·일시중지·종료·차단·이미 구독', (tester) async {
      final FakeSubscriptionCommerce port =
          FakeSubscriptionCommerce(balanceCents: 100000000);
      int already = 0;
      await _pumpEntry(tester, port, onAlreadySubscribed: () => already++);
      Future<void> attempt(String code) async {
        port.subscribeFailCode = code;
        await tester.tap(find.text('84,900원으로 구독하기'));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      await attempt('MENTOR_CAP_EXCEEDED');
      expect(find.text('정원이 찼어요'), findsOneWidget);
      await attempt('MENTOR_PAUSED');
      expect(find.text('이 멘토는 현재 일시 휴식 중입니다. 복귀 후 다시 구독해 주세요.'), findsOneWidget);
      await attempt('MENTOR_TERMINATED');
      expect(find.text('활동을 종료한 멘토라 구독할 수 없어요'), findsOneWidget);
      await attempt('BLOCKED');
      expect(find.text('차단 상태에서는 구독할 수 없어요'), findsOneWidget);
      // 이미 구독 → 시트를 닫고 호출부가 재조회.
      await attempt('ALREADY_SUBSCRIBED');
      expect(find.text('요금제를 골라주세요'), findsNothing);
      expect(already, 1);
      expect(find.textContaining('충전'), findsNothing);
    });

    testWidgets('본인인증 게이트 ON + 미인증 → 시트 대신 안내 · 결제 호출 0', (tester) async {
      final FakeSubscriptionCommerce port =
          FakeSubscriptionCommerce(balanceCents: 100000000, identityVerified: false);
      await _pumpEntry(tester, port, gate: true);
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      expect(find.text('본인인증 후 구독할 수 있어요'), findsOneWidget);
      expect(find.text('본인인증 하러 가기'), findsOneWidget);
      expect(find.text('요금제를 골라주세요'), findsNothing);
      expect(port.identityCalls, 1);
      expect(port.subscribeCalls, isEmpty);
    });

    testWidgets('게이트 ON + 판독 실패 → fail-closed(미인증 취급)', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce(
          balanceCents: 100000000, identityError: StateError('down'));
      await _pumpEntry(tester, port, gate: true);
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      expect(find.text('본인인증 후 구독할 수 있어요'), findsOneWidget);
      expect(find.text('요금제를 골라주세요'), findsNothing);
    });

    testWidgets('게이트 ON + 인증 → 시트', (tester) async {
      final FakeSubscriptionCommerce port =
          FakeSubscriptionCommerce(balanceCents: 100000000, identityVerified: true);
      await _pumpEntry(tester, port, gate: true);
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      expect(find.text('요금제를 골라주세요'), findsOneWidget);
      expect(port.identityCalls, 1);
    });

    testWidgets('게이트 OFF → 판독 없이 시트', (tester) async {
      final FakeSubscriptionCommerce port2 =
          FakeSubscriptionCommerce(balanceCents: 100000000, identityVerified: false);
      await _pumpEntry(tester, port2);
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      expect(find.text('요금제를 골라주세요'), findsOneWidget);
      expect(port2.identityCalls, 0);
    });

    testWidgets('게스트 → 로그인 안내 · 멘토 시점에는 그리지 않는다', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce();
      await _pumpEntry(tester, port, role: AppRole.guest);
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      expect(find.text('로그인하면 구독할 수 있어요.'), findsOneWidget);
      expect(find.text('요금제를 골라주세요'), findsNothing);

      await _pumpEntry(tester, port, role: AppRole.mentor);
      expect(find.text('구독하기'), findsNothing);
    });

    testWidgets('잔액 조회 실패 → 숫자 날조 없이 서버 판정에 맡긴다(버튼 활성)', (tester) async {
      final FakeSubscriptionCommerce port =
          FakeSubscriptionCommerce(balanceError: StateError('wallet down'));
      await _pumpEntry(tester, port);
      await tester.tap(find.text('구독하기'));
      await tester.pumpAndSettle();
      expect(find.text('확인하지 못했어요'), findsOneWidget);
      final FilledButton btn = tester.widget(find.widgetWithText(FilledButton, '84,900원으로 구독하기'));
      expect(btn.onPressed, isNotNull);
    });
  });

  group('문구 사전', () {
    test('구독 오류 문구 어디에도 충전 유도가 없다', () {
      const List<String> codes = <String>[
        'CASH_INSUFFICIENT', 'MENTOR_CAP_EXCEEDED', 'ALREADY_SUBSCRIBED', 'MENTOR_PAUSED',
        'MENTOR_TERMINATED', 'BLOCKED', 'MENTOR_NOT_OPEN_FOR_SUBSCRIPTIONS', 'MENTOR_NOT_APPROVED',
        'PLAN_AMOUNT_CHANGED', 'ROOM_ENSURE_FAILED', 'FINANCIAL_WRITE_ERROR', 'UNKNOWN_X',
      ];
      for (final String c in codes) {
        final String m = subscribeMessageForCode(c, const <String, dynamic>{});
        expect(m.contains('충전'), isFalse, reason: c);
        expect(m.contains(c), isFalse, reason: '코드 노출 금지: $c');
      }
      expect(subscribeMessageForCode('CASH_INSUFFICIENT', <String, dynamic>{'shortfall_cents': 3920000}),
          '잔액이 39,200원 부족해요');
      expect(refundMessageForCode('ALREADY_REQUESTED', const {}), '이미 신청한 환불이 있어요');
      expect(refundMessageForCode('REASON_TOO_SHORT', const {}).contains('5자'), isTrue);
    });

    test('uuid v4 형식', () {
      final String k = uuidV4();
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(k), isTrue);
      expect(uuidV4(), isNot(k));
    });
  });
}
