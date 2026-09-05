import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/mentor_plans_screen.dart';

import '../support/fake_mentor_console.dart';
import 'golden_harness.dart';

/// A-4b ⑤ 요금제 설정(C3) + 활성 토글 — 라이트 꺼짐 상태.
void main() {
  testWidgets('golden: a4b_mentor_plans_toggle', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      MentorPlansScreen(
        portOverride: FakeMentorConsole(
          planPrices: const MentorPlanPrices(
            limitedWon: 29900,
            standardWon: 84900,
            premiumWon: 174900,
            active: <MentorPlanTier, bool>{MentorPlanTier.limited: false},
          ),
          iqPriceWon: 2500,
        ),
      ),
      role: AppRole.mentor,
    );
    expect(find.text('꺼짐 · 새 구독만 막히고 기존 구독은 그대로예요'), findsOneWidget);
    await expectScreenGolden(tester, 'a4b_mentor_plans_toggle');
  });
}
