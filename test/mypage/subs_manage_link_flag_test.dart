import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/ui/sections/student_subscription_section.dart';

import '../subscription/fake_subscription_commerce.dart';

/// A-4b ②: '구독 관리 (웹)' 링크·안내 카드는 사라지고, 구독 카드 자체가
/// 해지 예약·해지 취소를 앱에서 처리한다(플래그·웹 브릿지 0).
/// (종전 P0-3 플래그 연동 검증은 A-4b 로 폐기 — 보고서 '카피 단언 갱신' 참고.)
void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      );

  testWidgets('구독 카드는 웹 링크·안내 없이 앱 안에서 해지를 관리한다',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(StudentSubscriptionSection(
      subscriptions: <SubscriptionCardInfo>[
        SubscriptionCardInfo(
          mentorName: '김멘토',
          isActive: true,
          subscriptionId: 'sub-1',
          status: 'active',
          nextRenewal: DateTime(2026, 7, 27),
        ),
      ],
      onGoToQuestions: () {},
      port: FakeSubscriptionCommerce(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('구독 관리 (웹)'), findsNothing);
    expect(find.textContaining('웹'), findsNothing);
    expect(find.text('해지 예약'), findsOneWidget);
    // 구독 상태 조회 표시는 그대로.
    expect(find.text('김멘토'), findsOneWidget);
    expect(find.text('7월 27일에 갱신돼요'), findsOneWidget);
  });
}
