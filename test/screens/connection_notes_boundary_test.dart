import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/question_room/data/models/connection_note.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/ui/connection_notes_screen.dart';
import '../support/app_scope_test_harness.dart';

/// 연결노트 입력 경계 — 빈/공백 저장 차단, 초장문·이모지·특수문자 렌더.
/// 저장은 onSaveNote 주입으로 가로채 DB 비접촉.
void main() {
  Room room() => Room(
        id: 'room-1',
        studentId: 's1',
        mentorId: 'm1',
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );

  ConnectionNote note(String body) => ConnectionNote(
        id: 'n1',
        roomId: 'room-1',
        body: body,
        authorId: 'm1', // 상대(멘토) 노트로 렌더되게.
        authorRole: NoteAuthorRole.mentor,
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );

  Widget app(Widget home) => MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: home,
      );

  testWidgets('빈 문자열·공백만으로는 저장이 호출되지 않는다', (WidgetTester tester) async {
    final List<String> saved = <String>[];
    await tester.pumpScopedWidget(app(ConnectionNotesScreen(
      room: room(),
      mentorName: '김멘토',
      currentUserId: 's1',
      notesLoader: () async => <ConnectionNote>[],
      onSaveNote: (String body) async => saved.add(body),
    )));
    await tester.pumpAndSettle();

    // 빈 입력.
    await tester.tap(find.text('내 노트 저장'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);

    // 공백·개행만 — trim 후 빈 값이라 역시 저장 안 됨.
    await tester.enterText(find.byType(TextField), '   \n\t  ');
    await tester.tap(find.text('내 노트 저장'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.text('노트를 저장했어요.'), findsNothing);
  });

  testWidgets('앞뒤 공백은 trim 되어 저장된다', (WidgetTester tester) async {
    final List<String> saved = <String>[];
    await tester.pumpScopedWidget(app(ConnectionNotesScreen(
      room: room(),
      mentorName: '김멘토',
      currentUserId: 's1',
      notesLoader: () async => <ConnectionNote>[],
      onSaveNote: (String body) async => saved.add(body),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  중간 내용  ');
    await tester.tap(find.text('내 노트 저장'));
    await tester.pumpAndSettle();
    expect(saved, <String>['중간 내용']);
  });

  testWidgets('초장문(10k자)·이모지·특수문자 노트가 예외 없이 렌더된다', (WidgetTester tester) async {
    final String long = '가나다라마바사아자차카타파하 ' * 700; // 약 10.5k자
    const String tricky = '😀🧮 √(x²+1) ≤ ∑ <b>&amp;</b> "따옴표" \\백슬래시 %s ﷽';
    await tester.pumpScopedWidget(app(ConnectionNotesScreen(
      room: room(),
      mentorName: '김멘토',
      currentUserId: 's1',
      // 이모지 노트를 앞에 — 10k자 노트가 리스트 지연 빌드로 밀려도 검증 가능.
      notesLoader: () async => <ConnectionNote>[note(tricky), note(long)],
    )));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('😀🧮'), findsOneWidget);
  });
}
