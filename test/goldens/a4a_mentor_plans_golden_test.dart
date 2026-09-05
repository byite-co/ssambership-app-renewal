import 'package:flutter/material.dart' show Switch;
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/mentor_plans_screen.dart';

import '../support/fake_mentor_console.dart';
import 'golden_harness.dart';

/// A-4a #2·#3 요금제 + 개별질문 단가 — 현재 값 채움 상태.
void main() {
  testWidgets('golden: a4a_mentor_plans', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      MentorPlansScreen(
        portOverride: FakeMentorConsole(
          planPrices: const MentorPlanPrices(
            limitedWon: 29900,
            standardWon: 84900,
            premiumWon: 174900,
          ),
          iqPriceWon: 2500,
        ),
      ),
      role: AppRole.mentor,
    );
    // A-4b ⑤: 카드마다 활성 토글이 들어와 '저장하기' 는 뷰포트 아래로 내려갔다.
    expect(find.text('요금제마다 정할 수 있는 범위가 달라요'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));
    await expectScreenGolden(tester, 'a4a_mentor_plans');
  });
}
