import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/refresh/data_refresh_bus.dart';
import 'package:ssambership_app/features/subscription/data/subscription_commerce_models.dart';
import 'package:ssambership_app/features/subscription/ui/refund_request_screen.dart';

import '../support/app_scope_test_harness.dart';
import 'fake_subscription_commerce.dart';

RefundEstimate _est({
  int refundable = 5660000,
  int amount = 8490000,
  String rule = '1/3 전',
  String bracket = 'lt_1_3',
  bool usage = true,
  int elapsed = 5,
}) =>
    RefundEstimate(
      refundableCents: refundable,
      amountCents: amount,
      rule: rule,
      bracketReason: bracket,
      usageStarted: usage,
      elapsedDays: elapsed,
      periodDays: 30,
      remainingDays: 25,
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 10, 1),
    );

Future<void> _pump(WidgetTester tester, FakeSubscriptionCommerce port, {bool inNavigator = false, ValueChanged<bool?>? onResult}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final Widget screen = RefundRequestScreen(
    subscriptionId: 'sub-1',
    mentorName: '김멘토',
    planLabel: '스탠다드',
    port: port,
  );
  await tester.pumpWidget(const SizedBox.shrink()); // 같은 위치 재사용 방지 — initState 재실행.
  await tester.pumpScopedWidget(MaterialApp(
    home: inNavigator ? _Launcher(screen: screen, onResult: onResult) : screen,
  ));
  await tester.pumpAndSettle();
}

/// 결과(pop 값) 관찰용 런처 — '열기' → push → true 로 닫히면 'popped-true' 표시.
class _Launcher extends StatelessWidget {
  const _Launcher({required this.screen, this.onResult});
  final Widget screen;
  final ValueChanged<bool?>? onResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async {
            final bool? r = await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(builder: (_) => screen),
            );
            onResult?.call(r);
          },
          child: const Text('열기'),
        ),
      ),
    );
  }
}

void main() {
  group('환불 신청(A-4b ③)', () {
    testWidgets('예상액·근거 규칙 먼저 표시 · 결제액·차감·환불 예정', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce()..estimate = _est();
      await _pump(tester, port);
      expect(port.estimateCalls, <String>['sub-1']);
      expect(find.byKey(const ValueKey<String>('refund-estimate')), findsOneWidget);
      expect(find.text('56,600원'), findsNWidgets(2)); // 큰 숫자 + 환불 예정 줄.
      expect(find.text('1/3 전'), findsOneWidget);
      expect(find.text('기간의 1/3 전 — 결제액의 2/3'), findsOneWidget);
      expect(find.text('84,900원'), findsOneWidget);
      expect(find.text('이미 쓴 5일치'), findsOneWidget);
      expect(find.text('-28,300원'), findsOneWidget);
      expect(find.textContaining('충전'), findsNothing);
      expect(find.textContaining('웹'), findsNothing);
      // 사유 전이면 비활성.
      final FilledButton btn = tester.widget(find.widgetWithText(FilledButton, '환불 신청하기'));
      expect(btn.onPressed, isNull);
    });

    testWidgets('이용 개시 전 → 전액 · 0원이면 경고(신청은 가능)', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce()
        ..estimate = _est(refundable: 8490000, rule: '이용 개시 전', bracket: 'before_usage', usage: false, elapsed: 0);
      await _pump(tester, port);
      expect(find.text('이용 개시 전 — 전액'), findsOneWidget);
      expect(find.text('기준상 환불액이 0원이에요. 신청은 할 수 있지만 돌려받는 금액은 없어요.'), findsNothing);

      final FakeSubscriptionCommerce zero = FakeSubscriptionCommerce()
        ..estimate = _est(refundable: 0, rule: '1/2 후', bracket: 'ge_1_2', elapsed: 20);
      await _pump(tester, zero);
      expect(find.text('기준상 환불액이 0원이에요. 신청은 할 수 있지만 돌려받는 금액은 없어요.'), findsOneWidget);
      await tester.tap(find.text('실수로 결제했어요'));
      await tester.pumpAndSettle();
      final FilledButton btn = tester.widget(find.widgetWithText(FilledButton, '환불 신청하기'));
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('사유 선택 → 래퍼 호출(사유 문구) · 세대 신호 · pop(true)', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce()..estimate = _est();
      final int gen = DataRefreshBus.subscriptionGeneration.value;
      bool? popped;
      await _pump(tester, port, inNavigator: true, onResult: (bool? r) => popped = r);
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('답변이 너무 늦어요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('환불 신청하기'));
      await tester.pumpAndSettle();
      expect(port.refundCalls, hasLength(1));
      expect(port.refundCalls.single['id'], 'sub-1');
      expect(port.refundCalls.single['reason'], '답변이 너무 늦어요');
      expect(DataRefreshBus.subscriptionGeneration.value, gen + 1);
      expect(popped, isTrue);
      expect(find.byType(RefundRequestScreen), findsNothing);
    });

    testWidgets('그 밖의 이유: 5자 미만 차단 · 5자 이상 전송 · 2000자 상한', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce()..estimate = _est();
      await _pump(tester, port);
      await tester.tap(find.text('그 밖의 이유'));
      await tester.pumpAndSettle();
      expect(find.text('5자 이상 · 2000자까지'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '늦어요');
      await tester.pumpAndSettle();
      expect(find.text('사유를 5자 이상 적어 주세요'), findsOneWidget);
      FilledButton btn = tester.widget(find.widgetWithText(FilledButton, '환불 신청하기'));
      expect(btn.onPressed, isNull);
      await tester.enterText(find.byType(TextField), '답변이 기대와 달랐어요');
      await tester.pumpAndSettle();
      btn = tester.widget(find.widgetWithText(FilledButton, '환불 신청하기'));
      expect(btn.onPressed, isNotNull);
      final TextField field = tester.widget(find.byType(TextField));
      expect(field.maxLength, 2000);
      await tester.tap(find.text('환불 신청하기'));
      await tester.pumpAndSettle();
      expect(port.refundCalls.single['reason'], '답변이 기대와 달랐어요');
    });

    testWidgets('ALREADY_REQUESTED → 이미 신청한 환불이 있어요', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce()
        ..estimate = _est()
        ..refundFailCode = 'ALREADY_REQUESTED';
      await _pump(tester, port);
      await tester.tap(find.text('실수로 결제했어요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('환불 신청하기'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('refund-error')), findsOneWidget);
      expect(find.text('이미 신청한 환불이 있어요'), findsOneWidget);
      expect(find.byType(RefundRequestScreen), findsOneWidget); // 닫히지 않음.
    });

    testWidgets('예상액 조회 실패 → 재시도', (tester) async {
      final FakeSubscriptionCommerce port = FakeSubscriptionCommerce()..estimateError = StateError('down');
      await _pump(tester, port);
      expect(find.text('예상 환불액을 확인하지 못했어요'), findsOneWidget);
      port.estimateError = null;
      port.estimate = _est();
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('refund-estimate')), findsOneWidget);
      expect(port.estimateCalls, hasLength(2));
    });
  });
}
