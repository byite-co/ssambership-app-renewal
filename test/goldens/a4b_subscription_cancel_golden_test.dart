import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/ui/sections/student_subscription_section.dart';
import 'package:ssambership_app/shared/constants/app_constants.dart';

import '../subscription/fake_subscription_commerce.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// A-4b ② — 구독 현황 카드(해지 예약·해지 취소 버튼) 위에 해지 확인 시트(design-v3 §5-8).
/// 위험색은 확인 버튼에만. 남은 기간을 먼저 알린다.
void main() {
  testWidgets('golden: a4b_subscription_cancel_sheet', (WidgetTester tester) async {
    final List<SubscriptionCardInfo> cards = <SubscriptionCardInfo>[
      SubscriptionCardInfo(
        mentorName: kMentorName,
        isActive: true,
        subscriptionId: 'sub-1',
        status: 'active',
        planTier: 'premium',
        nextRenewal: DateTime(2026, 9, 9),
        usage: goldenUsage,
      ),
      SubscriptionCardInfo(
        mentorName: '박멘토',
        isActive: true,
        subscriptionId: 'sub-2',
        status: 'active',
        planTier: 'limited',
        nextRenewal: DateTime(2026, 9, 21),
        cancelAtPeriodEnd: true,
      ),
    ];
    await pumpGoldenScreen(
      tester,
      Scaffold(
        appBar: AppBar(title: const Text(AppConstants.myPageTitle)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: <Widget>[
            StudentSubscriptionSection(
              subscriptions: cards,
              onGoToQuestions: () {},
              port: FakeSubscriptionCommerce(),
            ),
          ],
        ),
      ),
      role: AppRole.student,
    );
    expect(find.text('9월 21일에 해지돼요'), findsOneWidget);
    expect(find.text('해지 취소'), findsOneWidget);
    await tester.tap(find.text('해지 예약'));
    await tester.pumpAndSettle();
    expect(find.text('정말 해지할까요?'), findsOneWidget);
    expect(find.text('다음 결제가 중단돼요. 9월 9일까지는 계속 쓸 수 있어요.'), findsOneWidget);
    await expectScreenGolden(tester, 'a4b_subscription_cancel_sheet');
  });
}
