import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/entitlement/weekly_question_usage.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';
import 'package:ssambership_app/features/question_room/data/question_room_write_repository.dart';
import 'package:ssambership_app/features/question_room/ui/question_list_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

/// 세션1 보정 1-3: 오답 표시 토글 — 학생 목록 화면에서 qna_flag_wrong_answer RPC 소비.
class _FakeRead extends QuestionRoomReadRepository {
  _FakeRead(this._threads);

  List<QuestionThread> _threads;
  set threadsData(List<QuestionThread> v) => _threads = v;

  @override
  Future<List<QuestionThread>> threads(String roomId) async => _threads;

  @override
  Future<WeeklyQuestionUsage?> weeklyUsage({
    required String studentId,
    required String mentorId,
  }) async =>
      null;
}

class _FakeWrite extends QuestionRoomWriteRepository {
  _FakeWrite({this.error});

  final Object? error;
  final List<(String, bool)> flagCalls = <(String, bool)>[];

  @override
  Future<void> flagWrongAnswer(String threadId, {bool isWrong = true}) async {
    flagCalls.add((threadId, isWrong));
    final Object? e = error;
    if (e != null) throw e;
  }
}

QuestionThread _thread({
  required ThreadStatus status,
  bool wrong = false,
}) {
  final DateTime now = DateTime(2026, 7, 1);
  return QuestionThread(
    id: 't1',
    roomId: 'r1',
    title: '미분 질문',
    status: status,
    isWrongAnswer: wrong,
    masteryStatus: wrong ? MasteryStatus.wrong : MasteryStatus.unknown,
    createdAt: now,
    updatedAt: now,
  );
}

Room _room() {
  final DateTime now = DateTime(2026, 7, 1);
  return Room(
    id: 'r1',
    studentId: 's-1',
    mentorId: 'm-1',
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRead read,
  required _FakeWrite write,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: QuestionListScreen(
      room: _room(),
      mentorName: '김선생',
      readRepository: read,
      writeRepository: write,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'confirmed 스레드: 학생에게 "오답으로 표시" 노출 → RPC 1회(isWrong=true) + 재조회 반영',
      (WidgetTester tester) async {
    final _FakeRead read =
        _FakeRead(<QuestionThread>[_thread(status: ThreadStatus.confirmed)]);
    final _FakeWrite write = _FakeWrite();
    await _pump(tester, read: read, write: write);

    expect(find.text('오답으로 표시'), findsOneWidget);

    // 성공 후 재조회는 서버 반영값(isWrongAnswer=true)으로 수렴.
    read.threadsData = <QuestionThread>[
      _thread(status: ThreadStatus.confirmed, wrong: true),
    ];
    await tester.tap(find.text('오답으로 표시'));
    await tester.pumpAndSettle();

    expect(write.flagCalls, <(String, bool)>[('t1', true)]);
    expect(find.text('오답 표시 해제'), findsOneWidget);
  });

  testWidgets('이미 오답인 스레드: "오답 표시 해제" → RPC(isWrong=false)',
      (WidgetTester tester) async {
    final _FakeRead read = _FakeRead(
        <QuestionThread>[_thread(status: ThreadStatus.confirmed, wrong: true)]);
    final _FakeWrite write = _FakeWrite();
    await _pump(tester, read: read, write: write);

    await tester.tap(find.text('오답 표시 해제'));
    await tester.pumpAndSettle();

    expect(write.flagCalls, <(String, bool)>[('t1', false)]);
  });

  testWidgets('RPC 실패 → 이전 상태 유지(라벨 그대로) + 재시도 안내, UI 위장 없음',
      (WidgetTester tester) async {
    final _FakeRead read =
        _FakeRead(<QuestionThread>[_thread(status: ThreadStatus.confirmed)]);
    final _FakeWrite write = _FakeWrite(error: const AppError('서버 오류'));
    await _pump(tester, read: read, write: write);

    await tester.tap(find.text('오답으로 표시'));
    await tester.pumpAndSettle();

    expect(find.textContaining('오답 표시에 실패했어요'), findsOneWidget);
    expect(find.text('오답으로 표시'), findsOneWidget); // 원상 유지
    expect(find.text('오답 표시 해제'), findsNothing);
  });

  testWidgets('답변 전(pending) 스레드에는 오답 토글 미노출', (WidgetTester tester) async {
    final _FakeRead read =
        _FakeRead(<QuestionThread>[_thread(status: ThreadStatus.pending)]);
    await _pump(tester, read: read, write: _FakeWrite());

    expect(find.text('오답으로 표시'), findsNothing);
    expect(find.text('오답 표시 해제'), findsNothing);
  });

  testWidgets('answered 스레드: 답변 확인 버튼과 오답 토글이 함께 노출',
      (WidgetTester tester) async {
    final _FakeRead read =
        _FakeRead(<QuestionThread>[_thread(status: ThreadStatus.answered)]);
    await _pump(tester, read: read, write: _FakeWrite());

    expect(find.text('답변 확인 완료'), findsOneWidget);
    expect(find.text('오답으로 표시'), findsOneWidget);
  });
}
