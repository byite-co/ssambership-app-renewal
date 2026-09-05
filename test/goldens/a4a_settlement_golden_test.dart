import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/ui/mentor_settlement_screen.dart';
import 'package:ssambership_app/features/mentor_console/ui/settlement_lines_screen.dart';

import '../support/fake_mentor_console.dart';
import '../support/mentor_console_fixtures.dart';
import 'golden_harness.dart';

/// A-4a #7 정산 조회 — 허브(계좌 미등록 경고 포함)와 건별 내역.
void main() {
  testWidgets('golden: a4a_mentor_settlement', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      MentorSettlementScreen(
        portOverride: FakeMentorConsole(
          summary: sampleSettlementSummary(registered: false),
        ),
      ),
      role: AppRole.mentor,
    );
    expect(find.text('431,200원'), findsOneWidget);
    expect(find.text('정산 계좌를 등록해 주세요'), findsOneWidget);
    await expectScreenGolden(tester, 'a4a_mentor_settlement');
  });

  testWidgets('golden: a4a_settlement_lines', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      SettlementLinesScreen(
        portOverride: FakeMentorConsole(lines: sampleSettlementLines()),
      ),
      role: AppRole.mentor,
    );
    expect(find.text('2026년 9월'), findsOneWidget);
    await expectScreenGolden(tester, 'a4a_settlement_lines');
  });
}
