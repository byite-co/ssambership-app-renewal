import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/entitlement/subscription_summary.dart';
import 'package:ssambership_app/core/refresh/data_refresh_bus.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/ui/sections/student_subscription_section.dart';
import 'package:ssambership_app/shared/labels/subscription_copy.dart';

import 'fake_subscription_commerce.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

SubscriptionCardInfo _card({
  String id = 'sub-1',
  bool scheduled = false,
  String status = 'active',
}) =>
    SubscriptionCardInfo(
      mentorName: '김멘토',
      isActive: true,
      subscriptionId: id,
      status: status,
      planTier: 'standard',
      nextRenewal: DateTime(2026, 9, 13),
      cancelAtPeriodEnd: scheduled,
    );

void main() {
  group('구독 해지 예약·취소(A-4b ②)', () {
    testWidgets('활성 카드: 해지 예약 → 확인 시트 문구 → 래퍼 호출 · 안내', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce();
      int changed = 0;
      final int gen = DataRefreshBus.subscriptionGeneration.value;
      await tester.pumpWidget(_wrap(StudentSubscriptionSection(
        subscriptions: <SubscriptionCardInfo>[_card()],
        onGoToQuestions: () {},
        port: port,
        onChanged: () => changed++,
      )));
      await tester.pumpAndSettle();
      expect(find.text('9월 13일에 갱신돼요'), findsOneWidget);
      expect(find.text('구독 관리 (웹)'), findsNothing);
      expect(find.textContaining('웹'), findsNothing);

      await tester.tap(find.text('해지 예약'));
      await tester.pumpAndSettle();
      expect(find.text('정말 해지할까요?'), findsOneWidget);
      expect(find.text('다음 결제가 중단돼요. 9월 13일까지는 계속 쓸 수 있어요.'), findsOneWidget);
      // 닫기 → 호출 0.
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
      expect(port.cancelCalls, isEmpty);

      await tester.tap(find.text('해지 예약'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '해지 예약').last); // 시트의 확인 버튼
      await tester.pumpAndSettle();
      expect(port.cancelCalls, <String>['sub-1']);
      expect(changed, 1);
      expect(DataRefreshBus.subscriptionGeneration.value, gen + 1);
      expect(find.text('9월 13일에 해지돼요. 그때까지는 계속 쓸 수 있어요.'), findsOneWidget);
    });

    testWidgets('해지 예정 카드: 해지돼요 문장 · 해지 취소 → 다음 결제 재진행 명시 → undo 호출', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce();
      await tester.pumpWidget(_wrap(StudentSubscriptionSection(
        subscriptions: <SubscriptionCardInfo>[_card(scheduled: true)],
        onGoToQuestions: () {},
        port: port,
      )));
      await tester.pumpAndSettle();
      expect(find.text('9월 13일에 해지돼요'), findsOneWidget);
      expect(find.text('해지 예정'), findsOneWidget); // status active + 플래그 → 배지.
      expect(find.text('해지 예약'), findsNothing);
      await tester.tap(find.text('해지 취소'));
      await tester.pumpAndSettle();
      expect(find.text('해지 예약을 취소할까요?'), findsOneWidget);
      expect(find.text('9월 13일에 스탠다드 요금제로 다음 결제가 캐시로 다시 진행돼요.'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '해지 취소').last); // 시트의 확인 버튼
      await tester.pumpAndSettle();
      expect(port.undoCalls, <String>['sub-1']);
      expect(find.text('해지 예약을 취소했어요. 구독이 그대로 이어져요.'), findsOneWidget);
    });

    testWidgets('실패 코드 → 문구 사전 · 만료 카드·id 없는 카드에는 버튼 없음', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce()
        ..cancelFailCode = 'SUBSCRIPTION_NOT_CURRENT';
      await tester.pumpWidget(_wrap(StudentSubscriptionSection(
        subscriptions: <SubscriptionCardInfo>[
          _card(),
          const SubscriptionCardInfo(mentorName: '박멘토', isActive: false, status: 'expired', subscriptionId: 'sub-2'),
          const SubscriptionCardInfo(mentorName: '이멘토', isActive: true),
        ],
        onGoToQuestions: () {},
        port: port,
      )));
      await tester.pumpAndSettle();
      expect(find.text('해지 예약'), findsOneWidget); // 김멘토만.
      await tester.tap(find.text('해지 예약'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '해지 예약').last); // 시트의 확인 버튼
      await tester.pumpAndSettle();
      expect(find.textContaining('진행 중인 구독만 해지 예약을 바꿀 수 있어요.'), findsOneWidget);
    });
  });

  group('해지 예정 판정(플래그 우선)', () {
    test('cancel_at_period_end=true 면 status active 여도 해지돼요 문장', () {
      final SubscriptionSummary sub = SubscriptionSummary(
        mentorId: 'm1',
        isActive: true,
        status: 'active',
        cancelAtPeriodEnd: true,
        nextRenewal: DateTime(2026, 9, 13),
      );
      expect(sub.isCancelScheduled, isTrue);
      expect(SubscriptionCopy.subscriptionSentence(sub), '9월 13일에 해지돼요');
      expect(
        SubscriptionCopy.subscriptionSentence(SubscriptionSummary(
          mentorId: 'm1', isActive: true, status: 'active', nextRenewal: DateTime(2026, 9, 13),
        )),
        '9월 13일에 갱신돼요',
      );
    });
  });
}
