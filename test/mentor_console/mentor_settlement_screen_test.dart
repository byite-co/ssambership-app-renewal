import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/mentor_settlement_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import '../support/app_scope_test_harness.dart';
import '../support/fake_mentor_console.dart';
import '../support/mentor_console_fixtures.dart';

/// 계좌 상태를 요약에 반영하고 조회 횟수를 세는 허브 전용 fake.
class _HubConsole extends FakeMentorConsole {
  _HubConsole({required bool registered})
      : super(
          summary: sampleSettlementSummary(registered: registered),
          payoutAccount: registered
              ? const PayoutAccountInfo(
                  bankName: '카카오뱅크', accountMasked: '****5678')
              : const PayoutAccountInfo(),
          fullName: '김서연',
          lines: sampleSettlementLines(),
        );

  int summaryLoads = 0;

  @override
  Future<SettlementSummary> loadSettlementSummary({DateTime? month}) async {
    summaryLoads += 1;
    final SettlementSummary base = await super.loadSettlementSummary();
    return SettlementSummary(
      month: base.month,
      runDate: base.runDate,
      payoutAccountRegistered: payoutAccount.registered,
      confirmedNetCents: base.confirmedNetCents,
      confirmedCount: base.confirmedCount,
      accruingNetCents: base.accruingNetCents,
      accruingCount: base.accruingCount,
      heldMentorAmountCents: base.heldMentorAmountCents,
      heldCount: base.heldCount,
      paidTotalNetCents: base.paidTotalNetCents,
      paidTotalCount: base.paidTotalCount,
      bySource: base.bySource,
    );
  }
}

/// 정산 허브(A-4a #7) — 이번 달 금액·지급일·소스별 분해·계좌 미등록 경고·진입.
void main() {
  void tallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(FakeMentorConsole port) => withTestAppScope(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: MentorSettlementScreen(portOverride: port),
        ),
        auth: TestAppAuth(role: AppRole.mentor, userId: 'm1'),
      );

  testWidgets('계좌 등록됨: 금액·입금일·소스별 금액을 RPC 값 그대로, 경고 없음', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final _HubConsole port = _HubConsole(registered: true);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    expect(find.text('2026년 9월 받을 금액'), findsOneWidget);
    expect(find.text('431,200원'), findsOneWidget);
    expect(find.text('9월 10일에 입금돼요'), findsOneWidget);
    expect(find.text('무엇으로 벌었나요'), findsOneWidget);
    expect(find.text('4명'), findsOneWidget);
    expect(find.text('380,000원'), findsOneWidget);
    expect(find.text('3건'), findsOneWidget);
    expect(find.text('60,000원'), findsOneWidget);
    expect(find.text('적립 중 · 2건'), findsOneWidget);
    expect(find.text('보류 · 1건'), findsOneWidget);
    expect(find.text('지금까지 지급 · 18건'), findsOneWidget);
    expect(find.text('2,100,000원'), findsOneWidget);
    expect(find.text('등록됨'), findsOneWidget);

    expect(find.text('정산 계좌를 등록해 주세요'), findsNothing);
    expect(find.text('계좌 등록하기'), findsNothing);
    // 충전 유도 0.
    expect(find.textContaining('충전'), findsNothing);
  });

  testWidgets('계좌 미등록: 이월 경고 + 등록 진입 → 등록하고 돌아오면 요약을 다시 읽는다', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final _HubConsole port = _HubConsole(registered: false);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    expect(find.text('정산 계좌를 등록해 주세요'), findsOneWidget);
    expect(find.text('등록하지 않으면 9월 10일 지급이 다음 달로 미뤄져요.'),
        findsOneWidget);
    expect(find.text('미등록'), findsOneWidget);
    expect(port.summaryLoads, 1);

    await tester.tap(find.text('계좌 등록하기'));
    await tester.pumpAndSettle();
    expect(find.text('등록하기'), findsOneWidget); // PayoutAccountScreen.

    await tester.tap(find.text('은행을 선택해 주세요'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('카카오뱅크'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '3333012345678');
    await tester.pumpAndSettle();
    await tester.tap(find.text('등록하기'));
    await tester.pumpAndSettle();

    // 돌아온 허브는 요약을 다시 읽고 경고가 사라진다.
    expect(port.summaryLoads, 2);
    expect(find.text('정산 계좌를 등록해 주세요'), findsNothing);
    expect(find.text('등록됨'), findsOneWidget);
  });

  testWidgets('건별 내역 보기 → 내역 화면, 요금제 행 → 요금제 화면', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final _HubConsole port = _HubConsole(registered: true);
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    await tester.tap(find.text('건별 내역 보기'));
    await tester.pumpAndSettle();
    expect(find.text('건별 내역'), findsOneWidget);
    expect(find.text('2026년 9월'), findsOneWidget);
    await tester.tap(find.byTooltip('뒤로'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('요금제 · 개별질문 단가'));
    await tester.pumpAndSettle();
    expect(find.text('저장하기'), findsOneWidget); // MentorPlansScreen.
  });

  testWidgets('조회 실패 → 오류 + 다시 시도 → 복구', (WidgetTester tester) async {
    tallSurface(tester);
    final _HubConsole port = _HubConsole(registered: true)
      ..loadFailure = const AppError('네트워크 오류');
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();

    expect(find.text('정산 정보를 불러오지 못했어요'), findsOneWidget);
    port.loadFailure = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('431,200원'), findsOneWidget);
  });

  testWidgets('확정 건이 0이면 입금일 대신 "아직 확정된 정산이 없어요"', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    final FakeMentorConsole port = FakeMentorConsole(
      summary: const SettlementSummary(
        month: '2026-09',
        runDate: '2026-09-10',
        payoutAccountRegistered: true,
        confirmedNetCents: 0,
        confirmedCount: 0,
        accruingNetCents: 0,
        accruingCount: 0,
        heldMentorAmountCents: 0,
        heldCount: 0,
        paidTotalNetCents: 0,
        paidTotalCount: 0,
        bySource: <String, SettlementSourceAmount>{},
      ),
    );
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    expect(find.text('아직 확정된 정산이 없어요'), findsOneWidget);
    expect(find.text('0원'), findsWidgets);
  });
}
