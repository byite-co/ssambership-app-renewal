import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/refresh/data_refresh_bus.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/question_room_write_repository.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';

import '../support/app_scope_test_harness.dart';

class _FakeWrite extends QuestionRoomWriteRepository {
  _FakeWrite({this.error});
  Object? error;
  final List<String> confirmCalls = <String>[];
  @override
  Future<void> confirmThread(String threadId) async {
    confirmCalls.add(threadId);
    if (error != null) throw error!;
  }
}

QuestionThread _thread(ThreadStatus status) {
  final DateTime now = DateTime(2026, 9, 1);
  return QuestionThread(
    id: 't1',
    roomId: 'r1',
    title: '미분 질문',
    status: status,
    masteryStatus: MasteryStatus.unknown,
    createdAt: now,
    updatedAt: now,
  );
}

/// A-4b ⑨ 채팅 확인 바 — 웹 학생 대화 화면과 같은 위치·같은 RPC(`qna_confirm_thread`).
void main() {
  Future<void> pump(WidgetTester tester, ThreadStatus status, _FakeWrite write) async {
    await tester.pumpScopedWidget(MaterialApp(
      home: ChatScreen(thread: _thread(status), mentorName: '김선생', writeRepository: write),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('answered → 확인 바 · 탭 → RPC 1회 · 완료 표시 · 입력창 잠금', (tester) async {
    final _FakeWrite write = _FakeWrite();
    final int gen = DataRefreshBus.questionRoomsGeneration.value;
    await pump(tester, ThreadStatus.answered, write);
    expect(find.text('답변을 확인했어요'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // 확인 전엔 후속 질문 가능.
    await tester.tap(find.text('답변을 확인했어요'));
    await tester.pump();
    await tester.pump();
    expect(write.confirmCalls, <String>['t1']);
    expect(find.text('답변 완료'), findsOneWidget); // 상태칩.
    expect(find.text('완료된 질문이에요. 새 질문을 작성해 주세요.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('답변을 확인했어요. 이 질문은 완료로 표시돼요.'), findsOneWidget);
    expect(DataRefreshBus.questionRoomsGeneration.value, gen + 1);
  });

  testWidgets('pending → 확인 바 없음 · confirmed 로 열면 처음부터 잠김', (tester) async {
    final _FakeWrite write = _FakeWrite();
    await pump(tester, ThreadStatus.pending, write);
    expect(find.text('답변을 확인했어요'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester, ThreadStatus.confirmed, write);
    expect(find.text('답변을 확인했어요'), findsNothing);
    expect(find.text('완료된 질문이에요. 새 질문을 작성해 주세요.'), findsOneWidget);
    expect(write.confirmCalls, isEmpty);
  });

  testWidgets('확인 실패 → 안내 · 입력창 유지', (tester) async {
    final _FakeWrite write = _FakeWrite(error: StateError('down'));
    await pump(tester, ThreadStatus.answered, write);
    await tester.tap(find.text('답변을 확인했어요'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('확인 처리에 실패했어요.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('답변을 확인했어요'), findsOneWidget);
  });
}
