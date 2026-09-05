import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/api_web_v1_envelope.dart';
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/data/mentor_console_repository.dart';
import 'package:ssambership_app/features/mentor_console/ui/mentor_plans_screen.dart';

import '../support/app_scope_test_harness.dart';
import '../support/fake_mentor_console.dart';

/// A-4b ⑤ 요금제 활성 토글 — `mentor_plan_active_set`. 끄면 새 구독만 막힌다.
void main() {
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(FakeMentorConsole port) => withTestAppScope(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: MentorPlansScreen(portOverride: port),
        ),
        auth: TestAppAuth(role: AppRole.mentor, userId: 'm1'),
      );

  const MentorPlanPrices prices = MentorPlanPrices(
    limitedWon: 29900,
    standardWon: 84900,
    premiumWon: 174900,
    active: <MentorPlanTier, bool>{MentorPlanTier.limited: false},
  );

  testWidgets('서버 값대로 토글 표시 · 끄기/켜기 → 래퍼 호출 · 안내', (tester) async {
    final FakeMentorConsole port = FakeMentorConsole(planPrices: prices, iqPriceWon: 2500);
    tallSurface(tester);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    final List<Switch> switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.map((Switch s) => s.value), <bool>[false, true, true]);
    expect(find.text('꺼짐 · 새 구독만 막히고 기존 구독은 그대로예요'), findsOneWidget);

    await tester.tap(find.byType(Switch).at(1)); // 스탠다드 끄기
    await tester.pumpAndSettle();
    expect(port.calls.last['name'], 'setPlanActive');
    expect(port.calls.last['tier'], 'standard');
    expect(port.calls.last['isActive'], false);
    expect(find.text('스탠다드 요금제를 껐어요. 새 구독만 막히고 기존 구독은 그대로예요.'), findsOneWidget);
    expect(tester.widgetList<Switch>(find.byType(Switch)).elementAt(1).value, isFalse);

    // 앞 스낵바가 사라진 뒤(큐 대기 방지) 다음 토글.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(0)); // 라이트 켜기
    await tester.pumpAndSettle();
    expect(port.calls.last['tier'], 'limited');
    expect(port.calls.last['isActive'], true);
    expect(find.text('라이트 요금제를 켰어요. 새 구독을 받아요.'), findsOneWidget);
  });

  testWidgets('LAST_ACTIVE_PLAN → 요금제 하나는 켜져 있어야 해요 · 토글 되돌림', (tester) async {
    final FakeMentorConsole port = FakeMentorConsole(planPrices: prices, iqPriceWon: 2500)
      ..failWith = ApiEnvelopeFailure(
        'LAST_ACTIVE_PLAN',
        planActiveMessageForCode('LAST_ACTIVE_PLAN', const <String, dynamic>{}),
        const <String, dynamic>{},
      );
    tallSurface(tester);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(2)); // 프리미엄 끄기 시도
    await tester.pumpAndSettle();
    expect(find.text('요금제 하나는 켜져 있어야 해요'), findsOneWidget);
    expect(tester.widgetList<Switch>(find.byType(Switch)).elementAt(2).value, isTrue);
  });

  test('is_active 행 값 파싱 — false 만 꺼짐, 누락은 서버 기본', () {
    final MentorPlanPrices p = MentorPlanPrices.fromRows(<Map<String, dynamic>>[
      <String, dynamic>{'plan_tier': 'limited', 'amount_cents': 2990000, 'is_active': false},
      <String, dynamic>{'plan_tier': 'standard', 'amount_cents': 8490000, 'is_active': true},
      <String, dynamic>{'plan_tier': 'premium', 'amount_cents': 17490000},
    ]);
    expect(p.isActive(MentorPlanTier.limited), isFalse);
    expect(p.isActive(MentorPlanTier.standard), isTrue);
    expect(p.isActive(MentorPlanTier.premium), isTrue);
    expect(planActiveMessageForCode('MENTOR_TERMINATED', const {}).contains('MENTOR'), isFalse);
  });
}
