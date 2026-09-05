import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/data/connection_note_errors.dart';
import 'package:ssambership_app/features/question_room/data/models/connection_note.dart';
import 'package:ssambership_app/features/question_room/data/models/question_message.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/question_room_write_repository.dart';
import 'package:ssambership_app/features/question_room/ui/connection_notes_screen.dart';
import 'package:ssambership_app/features/question_room/ui/mentor/mentor_answer_screen.dart';

import '../goldens/golden_fixtures.dart';
import '../support/app_scope_test_harness.dart';

/// A-5 §2-1 배너(접힘/펼침) · §2-2 답변 직후 시트(두 질문 + 나중에) · INSERT · 23505.
class _Write extends QuestionRoomWriteRepository {
  _Write({this.insertError});

  final Object? insertError;
  final List<String> inserted = <String>[];
  int appended = 0;

  @override
  Future<AppendedMessage> appendMessage({
    required String threadId,
    required String body,
  }) async {
    appended += 1;
    return AppendedMessage(
      message: QuestionMessage(
        id: 'm-$appended',
        threadId: threadId,
        authorId: kMentorId,
        body: body,
        createdAt: DateTime(2026, 9, 1, 11, 20),
      ),
      answeredTransition: true,
    );
  }

  @override
  Future<ConnectionNote> insertMyNote({
    required String roomId,
    required String body,
  }) async {
    inserted.add(body);
    final Object? e = insertError;
    if (e != null) throw e;
    return ConnectionNote(
      id: 'new',
      roomId: roomId,
      body: body,
      authorId: kMentorId,
      authorRole: NoteAuthorRole.mentor,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
  }
}

ConnectionNote _mentorNote(String id, String body, DateTime at) => ConnectionNote(
      id: id,
      roomId: kRoomId,
      body: body,
      authorId: kMentorId,
      authorRole: NoteAuthorRole.mentor,
      createdAt: at,
      updatedAt: at,
    );

void main() {
  Widget app({
    required List<ConnectionNote> notes,
    required _Write write,
  }) =>
      withTestAppScope(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: MentorAnswerScreen(
            thread: goldenThread(
              id: 't3',
              status: ThreadStatus.pending,
              title: '삼각함수 합성',
            ),
            studentName: kStudentName,
            room: goldenRoom(),
            currentUserIdOverride: kMentorId,
            readRepository: GoldenReadRepository(
              messageRows: goldenMessages('t3'),
              noteRows: notes,
            ),
            realtimeFactory: (String _) => GoldenNoopRealtime(),
            writeRepository: write,
          ),
        ),
        auth: TestAppAuth(role: AppRole.mentor, userId: kMentorId),
      );

  testWidgets('배너: 내 최신 노트 한 줄 접힘 → 탭하면 두 항목 + 전체 보기 → 연결노트', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(
      notes: <ConnectionNote>[
        _mentorNote('n1', '약점: 그래프를 그리지 않고 식만 봐요', DateTime(2026, 8, 18)),
        _mentorNote('n3',
            '약점: 분모 0 조건을 놓치는 패턴\n다음에 풀 유형: 좌·우극한이 다른 그래프 문제',
            DateTime(2026, 8, 30)),
        ConnectionNote(
          id: 's',
          roomId: kRoomId,
          body: '학생 메모',
          authorId: kStudentId,
          authorRole: NoteAuthorRole.student,
          createdAt: DateTime(2026, 8, 31),
          updatedAt: DateTime(2026, 8, 31),
        ),
      ],
      write: _Write(),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('에 남긴 노트 · 분모 0 조건을 놓치는 패턴'), findsOneWidget);
    expect(find.text('좌·우극한이 다른 그래프 문제'), findsNothing); // 접힘.

    await tester.tap(find.byIcon(Icons.push_pin_rounded));
    await tester.pumpAndSettle();
    expect(find.text('좌·우극한이 다른 그래프 문제'), findsOneWidget);
    expect(find.text('노트 2개 전체 보기'), findsOneWidget); // 학생 노트는 내 것이 아니다.

    await tester.tap(find.text('노트 2개 전체 보기'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionNotesScreen), findsOneWidget);
    expect(find.text('연결노트 · $kStudentName'), findsOneWidget);
  });

  testWidgets('노트가 없으면 배너는 "아직 노트가 없어요" 한 줄', (WidgetTester tester) async {
    await tester.pumpWidget(app(notes: <ConnectionNote>[], write: _Write()));
    await tester.pumpAndSettle();
    expect(find.text('아직 노트가 없어요 · 답변 후 한 줄 남겨보세요'), findsOneWidget);
  });

  testWidgets('답변 전송 직후 시트: 두 질문 → 저장하기 → INSERT + 배너 갱신 · 화면당 한 번', (
    WidgetTester tester,
  ) async {
    final _Write write = _Write();
    await tester.pumpWidget(app(notes: <ConnectionNote>[], write: write));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '분모가 0이 되는 값을 먼저 찾아요.');
    await tester.tap(find.byTooltip('답변 전송'));
    await tester.pumpAndSettle();

    expect(write.appended, 1);
    expect(find.text('답변을 보냈어요'), findsOneWidget);
    expect(find.text('$kStudentName 학생 노트에 한 줄 남길까요?'), findsOneWidget);
    expect(find.text('나중에'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, '예: 분모 조건을 확인하지 않고 대입해요'), '분모 조건을 안 봐요');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    expect(write.inserted, <String>['약점: 분모 조건을 안 봐요']);
    expect(find.text('노트를 남겼어요.'), findsOneWidget);
    expect(find.textContaining('에 남긴 노트 · 분모 조건을 안 봐요'), findsOneWidget);

    // 두 번째 답변에는 시트를 다시 띄우지 않는다(스낵바가 내려간 뒤).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '두 번째 답변');
    await tester.tap(find.byTooltip('답변 전송'));
    await tester.pumpAndSettle();
    expect(write.appended, 2);
    expect(find.text('답변을 보냈어요'), findsNothing);
  });

  testWidgets('시트에서 "나중에" → 아무것도 저장하지 않는다', (WidgetTester tester) async {
    final _Write write = _Write();
    await tester.pumpWidget(app(notes: <ConnectionNote>[], write: write));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '답변');
    await tester.tap(find.byTooltip('답변 전송'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    expect(write.inserted, isEmpty);
    expect(find.text('답변을 보냈어요'), findsNothing);
  });

  testWidgets('시트 저장이 UNIQUE(23505)에 막히면 지시서 문구', (WidgetTester tester) async {
    final _Write write = _Write(insertError: const NoteAlreadyExistsError());
    await tester.pumpWidget(app(notes: <ConnectionNote>[], write: write));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '답변');
    await tester.tap(find.byTooltip('답변 전송'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, '예: 좌·우극한이 다른 그래프 문제'), '그래프 문제');
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    expect(find.text('이미 남긴 노트가 있어요. 곧 여러 개를 남길 수 있게 돼요'), findsOneWidget);
  });
}
