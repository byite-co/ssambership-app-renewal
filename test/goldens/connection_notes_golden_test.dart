import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/ui/connection_notes_screen.dart';

import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 연결노트 — 상대(멘토) 노트 카드 + 내(학생) 노트 에디터(기존 본문 시드).
void main() {
  testWidgets('golden: connection_notes', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      ConnectionNotesScreen(
        room: goldenRoom(),
        mentorName: kMentorName,
        currentUserId: kStudentId,
        notesLoader: () async => goldenNotes(),
        onSaveNote: (String _) async {},
      ),
      role: AppRole.student,
    );
    await expectScreenGolden(tester, 'connection_notes');
  });
}
