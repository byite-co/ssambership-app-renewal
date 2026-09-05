import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/subscription/data/subscription_commerce_models.dart';
import 'package:ssambership_app/features/subscription/ui/refund_request_screen.dart';

import '../subscription/fake_subscription_commerce.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// A-4b ③ — 환불 신청(design-v3 §5-9): 예상액 크게 · 근거 규칙 · 사유 선택 · 신청 버튼.
void main() {
  testWidgets('golden: a4b_refund_request', (WidgetTester tester) async {
    final FakeSubscriptionCommerce port = FakeSubscriptionCommerce()
      ..estimate = RefundEstimate(
        refundableCents: 8745000,
        amountCents: 17490000,
        rule: '1/2 전',
        bracketReason: 'lt_1_2',
        usageStarted: true,
        elapsedDays: 12,
        periodDays: 30,
        remainingDays: 18,
        periodStart: DateTime(2026, 8, 27),
        periodEnd: DateTime(2026, 9, 26),
      );
    await pumpGoldenScreen(
      tester,
      RefundRequestScreen(
        subscriptionId: 'sub-1',
        mentorName: kMentorName,
        planLabel: '프리미엄',
        port: port,
      ),
      role: AppRole.student,
    );
    await tester.tap(find.text('실수로 결제했어요'));
    await tester.pumpAndSettle();
    expect(find.text('87,450원'), findsNWidgets(2));
    expect(find.text('이미 쓴 12일치'), findsOneWidget);
    expect(find.textContaining('충전'), findsNothing);
    await expectScreenGolden(tester, 'a4b_refund_request');
  });
}
