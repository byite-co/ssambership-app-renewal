import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/question_attachment.dart';
import 'package:ssambership_app/features/question_room/data/models/question_message.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';
import 'package:ssambership_app/features/question_room/data/thread_realtime.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';
import 'package:ssambership_app/features/question_room/ui/mentor/mentor_answer_screen.dart';

/// N21 화면 계약 — 학생 채팅·멘토 답변 두 표면의 페이지 로드/이전 병합/커서.
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

QuestionMessage _msg(String thread, int i) => QuestionMessage(
      id: 'm-$thread-${i.toString().padLeft(4, '0')}',
      threadId: thread,
      authorId: 'u1',
      body: '$thread 본문 $i',
      createdAt: DateTime.utc(2026, 7, 1).add(Duration(minutes: i)),
    );

/// 스레드별 데이터셋을 가진 페이징 fake — 호출 로그로 계약을 검증한다.
class _FakePagingRead extends QuestionRoomReadRepository {
  _FakePagingRead(this.byThread);

  final Map<String, List<QuestionMessage>> byThread; // asc 저장
  final List<String> recentCalls = <String>[];
  final List<({String thread, MessageCursor cursor, int limit})> beforeCalls =
      <({String thread, MessageCursor cursor, int limit})>[];

  @override
  Future<List<QuestionMessage>> recentMessages(String threadId,
      {required int limit}) async {
    recentCalls.add(threadId);
    final List<QuestionMessage> all = byThread[threadId] ?? <QuestionMessage>[];
    return all.length <= limit ? all : all.sublist(all.length - limit);
  }

  @override
  Future<List<QuestionMessage>> messagesBefore(String threadId,
      {required MessageCursor cursor, required int limit}) async {
    beforeCalls.add((thread: threadId, cursor: cursor, limit: limit));
    final List<QuestionMessage> all = byThread[threadId] ?? <QuestionMessage>[];
    final List<QuestionMessage> older = all
        .where((QuestionMessage m) =>
            m.createdAt.isBefore(cursor.createdAt) ||
            (m.createdAt.isAtSameMomentAs(cursor.createdAt) &&
                m.id.compareTo(cursor.id) < 0))
        .toList();
    return older.length <= limit ? older : older.sublist(older.length - limit);
  }

  @override
  Future<List<QuestionAttachment>> attachments(String threadId) async =>
      <QuestionAttachment>[];
}

QuestionThread _thread(String id) {
  final DateTime now = DateTime(2026, 7, 1);
  return QuestionThread(
    id: id,
    roomId: 'r1',
    title: '제목-$id',
    status: ThreadStatus.pending,
    masteryStatus: MasteryStatus.unknown,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  Widget student(_FakePagingRead read, String threadId) => MaterialApp(
        home: ChatScreen(
          key: ValueKey<String>(threadId), // 실제 내비게이션처럼 스레드별 새 State
          thread: _thread(threadId),
          mentorName: '김선생',
          readRepository: read,
          realtimeFactory: (String _) => _NoopRealtime(),
        ),
      );

  Widget mentor(_FakePagingRead read, String threadId) => MaterialApp(
        home: MentorAnswerScreen(
          key: ValueKey<String>(threadId),
          thread: _thread(threadId),
          studentName: '학생A',
          readRepository: read,
          realtimeFactory: (String _) => _NoopRealtime(),
        ),
      );

  Future<void> scrollToTop(WidgetTester tester) async {
    // 초기 로드는 맨 아래로 점프한다 — 버튼(리스트 최상단)은 사용자가 위로
    // 스크롤해야 보인다(빌더 리스트라 뷰포트 밖은 컬링).
    final ScrollableState s =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    s.position.jumpTo(s.position.minScrollExtent);
    await tester.pumpAndSettle();
  }

  group('학생 채팅(N21)', () {
    testWidgets('풀 페이지(200) → 이전 버튼 노출, 탭 시 oldest 커서로 병합',
        (WidgetTester tester) async {
      final _FakePagingRead read =
          _FakePagingRead(<String, List<QuestionMessage>>{
        'tA': <QuestionMessage>[for (int i = 0; i < 250; i++) _msg('tA', i)],
      });
      await tester.pumpWidget(student(read, 'tA'));
      await tester.pumpAndSettle();

      expect(read.recentCalls, <String>['tA']);
      await scrollToTop(tester);
      expect(find.text('이전 대화 불러오기'), findsOneWidget);

      await tester.tap(find.text('이전 대화 불러오기'));
      await tester.pumpAndSettle();

      expect(read.beforeCalls.length, 1);
      // 커서 = 로드된 가장 오래된 행(최신 200 중 첫 행 = i=50).
      expect(read.beforeCalls.single.cursor.id, 'm-tA-0050');
      expect(read.beforeCalls.single.limit, 200);
      // 남은 50건 병합 후 — 짧은 페이지였으므로 버튼 소멸(hasMore=false).
      expect(find.text('이전 대화 불러오기'), findsNothing);
    });

    testWidgets('짧은 첫 페이지(<200) → 이전 버튼 미노출', (WidgetTester tester) async {
      final _FakePagingRead read =
          _FakePagingRead(<String, List<QuestionMessage>>{
        'tA': <QuestionMessage>[for (int i = 0; i < 5; i++) _msg('tA', i)],
      });
      await tester.pumpWidget(student(read, 'tA'));
      await tester.pumpAndSettle();
      expect(find.text('이전 대화 불러오기'), findsNothing);
    });

    testWidgets('질문 전환 — 새 스레드는 새 커서·새 목록(이전 질문 누출 0)',
        (WidgetTester tester) async {
      final _FakePagingRead read =
          _FakePagingRead(<String, List<QuestionMessage>>{
        'tA': <QuestionMessage>[for (int i = 0; i < 250; i++) _msg('tA', i)],
        'tB': <QuestionMessage>[for (int i = 0; i < 3; i++) _msg('tB', i)],
      });
      await tester.pumpWidget(student(read, 'tA'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(student(read, 'tB'));
      await tester.pumpAndSettle();

      expect(read.recentCalls, <String>['tA', 'tB']);
      expect(
          find.textContaining('tB 본문 0', findRichText: true), findsOneWidget);
      expect(find.textContaining('tA 본문', findRichText: true), findsNothing,
          reason: '이전 질문 페이지 누출 금지');
      expect(find.text('이전 대화 불러오기'), findsNothing,
          reason: '새 스레드(3건)에는 hasMore 없음 — 커서 초기화');
    });
  });

  group('멘토 답변(N21)', () {
    testWidgets('풀 페이지 → 이전 버튼 → 커서 병합(멘토 표면 동일 계약)',
        (WidgetTester tester) async {
      final _FakePagingRead read =
          _FakePagingRead(<String, List<QuestionMessage>>{
        'tM': <QuestionMessage>[for (int i = 0; i < 201; i++) _msg('tM', i)],
      });
      await tester.pumpWidget(mentor(read, 'tM'));
      await tester.pumpAndSettle();

      expect(read.recentCalls, <String>['tM']);
      await scrollToTop(tester);
      expect(find.text('이전 대화 불러오기'), findsOneWidget);

      await tester.tap(find.text('이전 대화 불러오기'));
      await tester.pumpAndSettle();
      expect(read.beforeCalls.single.cursor.id, 'm-tM-0001');
      expect(find.text('이전 대화 불러오기'), findsNothing);
    });
  });
}
