import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/ui/new_question_screen.dart';

import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 새 질문 작성(design-v3 §3-3) — 제목·과목 칩·내용 입력(#E9EBEF) + 하단 '질문 보내기'.
void main() {
  testWidgets('golden: student_new_question', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      NewQuestionScreen(
        room: goldenRoom(),
        readRepository: GoldenReadRepository(usage: goldenUsage),
      ),
      role: AppRole.student,
    );
    expect(find.text('질문 보내기'), findsOneWidget);
    await expectScreenGolden(tester, 'student_new_question');
  });
}
