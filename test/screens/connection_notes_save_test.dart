import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/connection_note.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/ui/connection_notes_screen.dart';
import '../support/app_scope_test_harness.dart';

Room _room() => Room(
      id: 'r1',
      studentId: 's1',
      mentorId: 'm1',
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

ConnectionNote _note(
  String id,
  NoteAuthorRole role,
  String body,
  String authorId,
) =>
    ConnectionNote(
      id: id,
      roomId: 'r1',
      body: body,
      authorId: authorId,
      authorRole: role,
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

void main() {
  testWidgets('상대 노트 렌더 + 내 노트 저장이 save 경로(본인 author)를 호출',
      (WidgetTester tester) async {
    String? saved;
    await tester.pumpScopedWidget(MaterialApp(
      home: ConnectionNotesScreen(
        room: _room(),
        mentorName: '김멘토',
        notesLoader: () async => <ConnectionNote>[
          _note('n1', NoteAuthorRole.mentor, '멘토가 남긴 노트', 'm1'),
        ],
        onSaveNote: (String body) async {
          saved = body;
        },
      ),
    ));
    await tester.pumpAndSettle();

    // 상대(멘토) 노트가 보인다.
    expect(find.text('멘토가 남긴 노트'), findsOneWidget);
    // 내 노트 에디터 + 저장 버튼.
    expect(find.text('내 노트 저장'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '내가 쓴 메모');
    await tester.tap(find.text('내 노트 저장'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 실제 저장 경로(write repo.upsertMyNote 자리)가 내가 쓴 본문으로 호출됨.
    expect(saved, '내가 쓴 메모');
  });
}
