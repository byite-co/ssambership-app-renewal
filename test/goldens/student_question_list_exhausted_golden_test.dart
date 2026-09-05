import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/core/entitlement/weekly_question_usage.dart';
import 'package:ssambership_app/features/question_room/ui/question_list_screen.dart';

import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 이번 주 질문을 다 썼을 때(design-v3 §3-4) — 막지 않고 하단 바에서 두 갈래.
/// 충전·상위 요금제 유도 버튼은 없다(커머스 제로).
void main() {
  testWidgets('golden: student_question_list_exhausted',
      (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      QuestionListScreen(
        room: goldenRoom(),
        mentorName: kMentorName,
        sub: goldenSubscription(),
        readRepository: GoldenReadRepository(
          threadRows: goldenThreads(),
          usage: WeeklyQuestionUsage(
            used: 5,
            limit: 5,
            remaining: 0,
            canAsk: false,
            planTier: 'standard',
            weekEnd: DateTime(2026, 7, 9),
          ),
        ),
      ),
      role: AppRole.student,
    );
    expect(find.text('이번 주 질문을 다 썼어요'), findsOneWidget);
    expect(find.text('개별질문으로 지금 물어보기'), findsOneWidget);
    expect(find.textContaining('충전'), findsNothing);
    expect(find.textContaining('상위 요금제'), findsNothing);
    await expectScreenGolden(tester, 'student_question_list_exhausted');
  });
}
