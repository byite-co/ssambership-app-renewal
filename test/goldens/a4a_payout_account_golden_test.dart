import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/ui/payout_account_screen.dart';

import '../support/fake_mentor_console.dart';
import 'golden_harness.dart';

/// A-4a #1 정산 계좌 등록 — 미등록 상태(경고 + 빈 폼 + 예금주 고정).
void main() {
  testWidgets('golden: a4a_payout_account', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      PayoutAccountScreen(portOverride: FakeMentorConsole(fullName: '김서연')),
      role: AppRole.mentor,
    );
    expect(find.text('등록하기'), findsOneWidget);
    await expectScreenGolden(tester, 'a4a_payout_account');
  });
}
