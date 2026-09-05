import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/data/connection_note_errors.dart';
import 'package:ssambership_app/features/question_room/data/models/connection_note.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/question_room_write_repository.dart';
import 'package:ssambership_app/features/question_room/ui/connection_notes_screen.dart';

import '../support/app_scope_test_harness.dart';

/// A-5 연결노트 — 타임라인(created_at 최신순 · 건수 가정 없음) · 학생 요약 ·
/// 멘토 두 질문 · INSERT 전용 저장 · 23505 문구.
class _InsertOnlyWrite extends QuestionRoomWriteRepository {
  _InsertOnlyWrite({this.error});

  final Object? error;
  final List<String> inserted = <String>[];

  @override
  Future<ConnectionNote> insertMyNote({
    required String roomId,
    required String body,
  }) async {
    inserted.add('$roomId|$body');
    final Object? e = error;
    if (e != null) throw e;
    return ConnectionNote(
      id: 'new',
      roomId: roomId,
      body: body,
      authorId: 's1',
      authorRole: NoteAuthorRole.student,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
  }
}

Room _room() => Room(
      id: 'r1',
      studentId: 's1',
      mentorId: 'm1',
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

ConnectionNote _note(String id, NoteAuthorRole role, String body, DateTime at) =>
    ConnectionNote(
      id: id,
      roomId: 'r1',
      body: body,
      authorId: role == NoteAuthorRole.mentor ? 'm1' : 's1',
      authorRole: role,
      createdAt: at,
      updatedAt: at,
    );

List<ConnectionNote> _history() => <ConnectionNote>[
      _note('n1', NoteAuthorRole.mentor, '약점: 그래프를 그리지 않고 식만 봐요', DateTime(2026, 8, 18)),
      _note('n2', NoteAuthorRole.student, '공식은 외웠는데 조건을 안 봤다', DateTime(2026, 8, 20)),
      _note('n3', NoteAuthorRole.mentor,
          '약점: 분모 0 조건을 놓치는 패턴\n다음에 풀 유형: 좌·우극한이 다른 그래프 문제', DateTime(2026, 8, 30)),
    ];

void main() {
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app({
    required String uid,
    required List<ConnectionNote> notes,
    required _InsertOnlyWrite write,
  }) =>
      withTestAppScope(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: ConnectionNotesScreen(
            room: _room(),
            mentorName: uid == 'm1' ? '최하원' : '김민서',
            currentUserId: uid,
            notesLoader: () async => notes,
          ),
        ),
        dependencies: testAppDependencies(
          auth: TestAppAuth(
            role: uid == 'm1' ? AppRole.mentor : AppRole.student,
            userId: uid,
          ),
          questionRoomWrite: write,
        ),
      );

  testWidgets('학생: 최신 멘토 노트 요약이 맨 위, 타임라인은 최신순 전부 · 저장은 INSERT', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final _InsertOnlyWrite write = _InsertOnlyWrite();
    await tester.pumpWidget(app(uid: 's1', notes: _history(), write: write));
    await tester.pumpAndSettle();

    expect(find.text('김민서 멘토가 본 나'), findsOneWidget);
    expect(find.text('지금 약한 것'), findsOneWidget);
    expect(find.text('다음에 풀어볼 유형'), findsOneWidget);
    // 요약에 올린 최신 멘토 노트(8/30)는 타임라인에서 빼고, 나머지는 최신순.
    expect(find.text('지난 노트 2개'), findsOneWidget);
    expect(find.text('2026년 8월 30일'), findsNothing);
    final double y20 = tester.getTopLeft(find.text('2026년 8월 20일')).dy;
    final double y18 = tester.getTopLeft(find.text('2026년 8월 18일')).dy;
    expect(y20, lessThan(y18));
    expect(find.text('분모 0 조건을 놓치는 패턴'), findsOneWidget); // 요약에 한 번만.
    expect(find.text('공식은 외웠는데 조건을 안 봤다'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  이번 주는 극한만 팠다 ');
    await tester.tap(find.text('내 노트 저장'));
    await tester.pumpAndSettle();
    expect(write.inserted, <String>['r1|이번 주는 극한만 팠다']);
    expect(find.text('노트를 저장했어요.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });

  testWidgets('학생: 노트 0개면 빈 상태 + 저장 칸 유지', (WidgetTester tester) async {
    await tester.pumpWidget(app(
      uid: 's1',
      notes: <ConnectionNote>[],
      write: _InsertOnlyWrite(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('아직 노트가 없어요'), findsOneWidget);
    expect(find.text('질문을 주고받으면 멘토가 약한 부분을 적어줘요'), findsOneWidget);
    expect(find.text('내 노트 저장'), findsOneWidget);
  });

  testWidgets('두 번째 노트가 UNIQUE(23505)에 막히면 지시서 문구 그대로', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final _InsertOnlyWrite write =
        _InsertOnlyWrite(error: const NoteAlreadyExistsError());
    await tester.pumpWidget(app(uid: 's1', notes: _history(), write: write));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '두 번째');
    await tester.tap(find.text('내 노트 저장'));
    await tester.pumpAndSettle();
    expect(find.text('이미 남긴 노트가 있어요. 곧 여러 개를 남길 수 있게 돼요'), findsOneWidget);
    expect(find.textContaining('저장에 실패했어요'), findsNothing);
  });

  testWidgets('멘토: 두 질문으로 쓰고 규약 본문으로 INSERT · 빈 상태는 작성 예시', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final _InsertOnlyWrite write = _InsertOnlyWrite();
    await tester.pumpWidget(app(uid: 'm1', notes: <ConnectionNote>[], write: write));
    await tester.pumpAndSettle();

    expect(find.text('연결노트 · 최하원'), findsOneWidget);
    expect(find.text('이렇게 씁니다'), findsOneWidget);
    expect(find.text('노트 저장'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));

    await tester.tap(find.text('노트 저장'));
    await tester.pumpAndSettle();
    expect(write.inserted, isEmpty); // 둘 다 비면 비활성.

    await tester.enterText(find.byType(TextField).first, '분모 조건을 확인하지 않고 대입해요');
    await tester.enterText(find.byType(TextField).last, '좌·우극한이 다른 그래프 문제');
    await tester.pumpAndSettle();
    await tester.tap(find.text('노트 저장'));
    await tester.pumpAndSettle();
    expect(
      write.inserted,
      <String>['r1|약점: 분모 조건을 확인하지 않고 대입해요\n다음에 풀 유형: 좌·우극한이 다른 그래프 문제'],
    );
  });

  testWidgets('멘토: 타임라인에 규약 노트는 두 항목으로, 자유 노트는 그대로', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    await tester.pumpWidget(app(uid: 'm1', notes: _history(), write: _InsertOnlyWrite()));
    await tester.pumpAndSettle();
    expect(find.text('타임라인'), findsOneWidget);
    expect(find.text('분모 0 조건을 놓치는 패턴'), findsOneWidget);
    expect(find.text('좌·우극한이 다른 그래프 문제'), findsOneWidget);
    expect(find.text('공식은 외웠는데 조건을 안 봤다'), findsOneWidget);
    expect(find.text('나'), findsNWidgets(2)); // 내(멘토) 노트 2건 표시.
  });
}
