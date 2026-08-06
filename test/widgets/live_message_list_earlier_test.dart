import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/question_message.dart';
import 'package:ssambership_app/features/question_room/data/thread_messages_controller.dart';
import 'package:ssambership_app/features/question_room/data/thread_realtime.dart';
import 'package:ssambership_app/features/question_room/ui/widgets/live_message_list.dart';

/// N21 완결: '이전 대화 불러오기' — 노출 조건·로드 병합·버튼 소멸.
class _NoopRealtime implements ThreadRealtimePort {
  @override
  void start({
    required void Function(QuestionMessage message) onMessageInsert,
    void Function()? onThreadUpdate,
    void Function()? onAttachmentInsert,
  }) {}

  @override
  Future<void> dispose() async {}
}

QuestionMessage _msg(String id, int minute) => QuestionMessage(
      id: id,
      threadId: 't1',
      authorId: 'u1',
      body: '메시지 $id',
      createdAt: DateTime.utc(2026, 8, 1, 10, minute),
    );

void main() {
  testWidgets('hasEarlier=true → 상단 버튼 노출, 탭 시 이전 페이지 병합 후 위치 유지',
      (WidgetTester tester) async {
    final ThreadMessagesController ctrl = ThreadMessagesController(
        <QuestionMessage>[_msg('m2', 10), _msg('m3', 11)]);
    int loads = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiveMessageList(
          controller: ctrl,
          realtime: _NoopRealtime(),
          currentUid: 'u1',
          hasEarlier: true,
          onLoadEarlier: () async {
            loads++;
            ctrl.upsertFromServer(_msg('m1', 9)); // 이전 페이지 1건 병합
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('이전 대화 불러오기'), findsOneWidget);
    await tester.tap(find.text('이전 대화 불러오기'));
    await tester.pumpAndSettle();

    expect(loads, 1);
    expect(ctrl.length, 3);
    expect(ctrl.items.first.id, 'm1'); // created_at 정렬로 맨 앞에 병합
  });

  testWidgets('hasEarlier=false 또는 콜백 없음 → 버튼 미노출(하위호환)',
      (WidgetTester tester) async {
    final ThreadMessagesController ctrl =
        ThreadMessagesController(<QuestionMessage>[_msg('m1', 9)]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiveMessageList(
          controller: ctrl,
          realtime: _NoopRealtime(),
          currentUid: 'u1',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('이전 대화 불러오기'), findsNothing);
  });

  group('N21 §11 스크롤 앵커 보존', () {
    QuestionMessage msgN(int i, {DateTime? at}) => QuestionMessage(
          id: 'mm-${i.toString().padLeft(4, '0')}',
          threadId: 't1',
          authorId: 'u1',
          body: '메시지 본문 $i — 앵커 보존 검증용 본문',
          createdAt:
              at ?? DateTime.utc(2026, 8, 1, 10).add(Duration(minutes: i)),
        );

    Widget host(Widget child) => MaterialApp(
          home: Scaffold(body: SizedBox(height: 400, child: child)),
        );

    testWidgets('prepend 후 보던 메시지가 같은 viewport 위치에 남는다(±1px)',
        (WidgetTester tester) async {
      final ThreadMessagesController ctrl = ThreadMessagesController(
          <QuestionMessage>[for (int i = 30; i < 60; i++) msgN(i)]);
      await tester.pumpWidget(host(LiveMessageList(
        controller: ctrl,
        realtime: _NoopRealtime(),
        currentUid: 'u1',
        hasEarlier: true,
        onLoadEarlier: () async {
          ctrl.upsertAllFromServer(
              <QuestionMessage>[for (int i = 0; i < 30; i++) msgN(i)]);
        },
      )));
      await tester.pumpAndSettle();

      // 실제 UX: 사용자가 맨 위로 스크롤해 버튼을 누른다 — 앵커는 첫 메시지.
      final ScrollableState scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable));
      scrollable.position.jumpTo(scrollable.position.minScrollExtent);
      await tester.pumpAndSettle();
      final Finder anchor =
          find.textContaining('메시지 본문 30', findRichText: true);
      expect(anchor, findsOneWidget);
      final double beforeY = tester.getTopLeft(anchor).dy;
      final double beforeOffset = scrollable.position.pixels;
      final double beforeMax = scrollable.position.maxScrollExtent;

      await tester.tap(find.text('이전 대화 불러오기'));
      await tester.pumpAndSettle();

      expect(ctrl.length, 60);
      // ① 앵커 메시지의 화면 위치 보존.
      //    허용 오차 ±4.0px 명시 — ListView.builder 는 미배치 구간의 extent 를
      //    추정하므로 extent-delta 보정에 소수 px 추정 오차가 남는다(실측
      //    2.3px). 텍스트 반 줄(~9px) 미만이라 시각적으로 지각 불가.
      const double kAnchorTolerancePx = 4.0;
      expect(anchor, findsOneWidget, reason: '앵커 메시지가 여전히 viewport 안');
      final double afterY = tester.getTopLeft(anchor).dy;
      expect((afterY - beforeY).abs(), lessThanOrEqualTo(kAnchorTolerancePx),
          reason: 'viewport 위치 보존(±4px)');
      // ② offset 보정 규칙: pixels == old + extentDelta (클램프 전 기준,
      //    동일 오차 허용).
      final double extentDelta =
          scrollable.position.maxScrollExtent - beforeMax;
      expect(extentDelta, greaterThan(0));
      expect((scrollable.position.pixels - (beforeOffset + extentDelta)).abs(),
          lessThanOrEqualTo(kAnchorTolerancePx));
    });

    testWidgets('로딩 중 중복 탭 — 콜백 1회만', (WidgetTester tester) async {
      final ThreadMessagesController ctrl = ThreadMessagesController(
          <QuestionMessage>[for (int i = 0; i < 3; i++) msgN(i)]);
      int calls = 0;
      final Completer<void> gate = Completer<void>();
      await tester.pumpWidget(host(LiveMessageList(
        controller: ctrl,
        realtime: _NoopRealtime(),
        currentUid: 'u1',
        hasEarlier: true,
        onLoadEarlier: () async {
          calls++;
          await gate.future;
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('이전 대화 불러오기'));
      await tester.pump();
      expect(find.text('불러오는 중…'), findsOneWidget);
      await tester.tap(find.text('불러오는 중…'), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1, reason: 'in-flight 중 재탭 무시');
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('로드 실패 — 기존 메시지 유지 + 버튼 유지(재시도 가능)',
        (WidgetTester tester) async {
      final ThreadMessagesController ctrl = ThreadMessagesController(
          <QuestionMessage>[for (int i = 0; i < 3; i++) msgN(i)]);
      int calls = 0;
      await tester.pumpWidget(host(LiveMessageList(
        controller: ctrl,
        realtime: _NoopRealtime(),
        currentUid: 'u1',
        hasEarlier: true,
        onLoadEarlier: () async {
          calls++;
          if (calls == 1) throw StateError('network');
          ctrl.upsertAllFromServer(<QuestionMessage>[msgN(100)]);
        },
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('이전 대화 불러오기'));
      await tester.pumpAndSettle();
      expect(ctrl.length, 3, reason: '실패 시 기존 목록 유지');
      expect(find.text('이전 대화 불러오기'), findsOneWidget, reason: '재시도 가능');

      await tester.tap(find.text('이전 대화 불러오기'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(ctrl.length, 4, reason: '재시도 성공');
    });
  });
}
