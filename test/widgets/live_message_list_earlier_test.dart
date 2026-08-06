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
    final ThreadMessagesController ctrl =
        ThreadMessagesController(<QuestionMessage>[_msg('m2', 10), _msg('m3', 11)]);
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
}
