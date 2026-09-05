import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/mentor_plans_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import '../support/app_scope_test_harness.dart';
import '../support/fake_mentor_console.dart';

/// 요금제(A-4a #2) + 개별질문 단가(#3) — 범위 밖 저장 비활성·문장 안내·F8 원자 저장.
void main() {
  /// 기본 테스트 표면(800×600)은 카드 4장 아래 저장 버튼이 지연 빌드 범위 밖이라
  /// 세로로 넉넉히 잡는다.
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
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

  Finder field(String title) => find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(Column),
        ).first,
        matching: find.byType(TextField),
      );

  testWidgets('현재 값이 채워지고 범위 안이면 저장 가능 → 세 등급 한 번에 저장', (
    WidgetTester tester,
  ) async {
    final FakeMentorConsole port = FakeMentorConsole(
      planPrices: const MentorPlanPrices(
        limitedWon: 29900,
        standardWon: 84900,
        premiumWon: 174900,
      ),
      iqPriceWon: 2500,
    );
    tallSurface(tester);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    expect(find.text('라이트 · 주 4문항'), findsOneWidget);
    expect(find.text('추천'), findsOneWidget);
    expect(find.text('29,900원 ~ 69,900원 사이'), findsOneWidget);

    await tester.enterText(field('프리미엄 · 질문 무제한'), '329900');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('저장하기'));
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    final Map<String, Object?> call = port.calls.single;
    expect(call['name'], 'setPlanPrices');
    expect(call['limited'], 29900);
    expect(call['standard'], 84900);
    expect(call['premium'], 329900);
    expect(find.text('요금제를 저장했어요.'), findsOneWidget);
  });

  testWidgets('범위 밖 값은 그 자리에서 문장으로 알리고 저장이 비활성', (
    WidgetTester tester,
  ) async {
    final FakeMentorConsole port = FakeMentorConsole(
      planPrices: const MentorPlanPrices(
        limitedWon: 29900,
        standardWon: 84900,
        premiumWon: 174900,
      ),
    );
    tallSurface(tester);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    await tester.enterText(field('프리미엄 · 질문 무제한'), '340000');
    await tester.pumpAndSettle();
    expect(find.text('174,900원 ~ 329,900원 사이로 적어 주세요'), findsOneWidget);

    await tester.ensureVisible(find.text('저장하기'));
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    expect(port.calls, isEmpty);
  });

  testWidgets('단가가 바뀌면 F8 뒤에 단가 RPC · 비우면 호출 없음', (
    WidgetTester tester,
  ) async {
    final FakeMentorConsole port = FakeMentorConsole(
      planPrices: const MentorPlanPrices(
        limitedWon: 30000,
        standardWon: 90000,
        premiumWon: 200000,
      ),
      iqPriceWon: 2500,
    );
    tallSurface(tester);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    await tester.enterText(field('지정 개별질문 답변 단가'), '3000');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('저장하기'));
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();

    expect(port.calls.map((Map<String, Object?> c) => c['name']),
        <String>['setPlanPrices', 'setIndividualQuestionPriceWon']);
    expect(port.calls.last['won'], 3000);
  });

  testWidgets('서버가 밴드 밖으로 거부하면 인라인 실패 문구', (WidgetTester tester) async {
    final FakeMentorConsole port = FakeMentorConsole(
      planPrices: const MentorPlanPrices(
        limitedWon: 30000,
        standardWon: 90000,
        premiumWon: 200000,
      ),
      failWith: const AppError('프리미엄 요금은 174,900원~329,900원 사이로 적어 주세요.'),
    );
    tallSurface(tester);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('저장하기'));
    await tester.tap(find.text('저장하기'));
    await tester.pumpAndSettle();
    expect(find.text('프리미엄 요금은 174,900원~329,900원 사이로 적어 주세요.'),
        findsOneWidget);
    expect(find.text('요금제를 저장했어요.'), findsNothing);
  });
}
