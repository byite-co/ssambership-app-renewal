import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/ui/connection_notes_screen.dart';

import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// A-5 §2-3 멘토 연결노트 — 두 질문 작성 카드 + 타임라인(기존 connection_notes 는 학생 변형).
void main() {
  testWidgets('golden: a4a_connection_notes_mentor', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      ConnectionNotesScreen(
        room: goldenRoom(),
        mentorName: kStudentName,
        currentUserId: kMentorId,
        notesLoader: () async => goldenNotes(),
        onSaveNote: (String _) async {},
      ),
      role: AppRole.mentor,
    );
    expect(find.text('연결노트 · $kStudentName'), findsOneWidget);
    await expectScreenGolden(tester, 'a4a_connection_notes_mentor');
  });
}
