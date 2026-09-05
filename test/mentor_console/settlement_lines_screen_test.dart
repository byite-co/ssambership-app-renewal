import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/data/mentor_console_models.dart';
import 'package:ssambership_app/features/mentor_console/ui/settlement_lines_screen.dart';
import 'package:ssambership_app/shared/errors/app_error.dart';

import '../support/app_scope_test_harness.dart';
import '../support/fake_mentor_console.dart';
import '../support/mentor_console_fixtures.dart';

/// 정산 건별 내역(A-4a #7) — 월 그룹·상태 5종·보류 사유·빈 상태.
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
          home: SettlementLinesScreen(portOverride: port),
        ),
        auth: TestAppAuth(role: AppRole.mentor, userId: 'm1'),
      );

  testWidgets('월별 그룹 최신순 · 상태 라벨 · 보류 사유 · 금액은 RPC 값 그대로', (
    WidgetTester tester,
  ) async {
    tallSurface(tester);
    await tester.pumpWidget(app(FakeMentorConsole(lines: sampleSettlementLines())));
    await tester.pumpAndSettle();

    expect(find.text('2026년 9월'), findsOneWidget);
    expect(find.text('2026년 8월'), findsOneWidget);
    expect(find.text('적립중'), findsOneWidget);
    expect(find.text('지급 예정'), findsOneWidget);
    expect(find.text('보류'), findsOneWidget);
    expect(find.text('지급 완료'), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);
    expect(find.text('분쟁 진행 중이라 보류됐어요'), findsOneWidget);
    expect(find.text('구독 정산 · 8/3~9/2'), findsOneWidget);
    expect(find.text('개별질문 답변'), findsNWidgets(2));
    expect(find.text('맞춤의뢰 주문'), findsOneWidget);
    expect(find.text('67,920원'), findsOneWidget);
    expect(find.text('65,679원'), findsOneWidget);
    expect(find.text('멘토 몫 2,400원 · 원천징수 79원 · 지급 예정 9월 10일'),
        findsOneWidget);
    expect(find.textContaining('지급 9월 10일'), findsOneWidget);
  });

  testWidgets('내역 없음 → 빈 상태', (WidgetTester tester) async {
    await tester.pumpWidget(app(FakeMentorConsole()));
    await tester.pumpAndSettle();
    expect(find.text('아직 정산 내역이 없어요'), findsOneWidget);
  });

  testWidgets('조회 실패 → 오류 + 다시 시도', (WidgetTester tester) async {
    final FakeMentorConsole port = FakeMentorConsole(
      lines: sampleSettlementLines(),
    )..loadFailure = const AppError('네트워크 오류');
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    expect(find.text('정산 내역을 불러오지 못했어요'), findsOneWidget);
    port.loadFailure = null;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('2026년 9월'), findsOneWidget);
  });

  testWidgets('5종 밖 상태는 "상태 확인 필요"로 드러낸다', (WidgetTester tester) async {
    final FakeMentorConsole port = FakeMentorConsole(
      lines: <SettlementLine>[
        SettlementLine.fromMap(<String, dynamic>{
          'source_type': 'subscription',
          'source_id': 'x',
          'occurred_at': '2026-09-01T00:00:00Z',
          'gross_cents': 100,
          'platform_fee_cents': 20,
          'mentor_amount_cents': 80,
          'withholding_cents': 0,
          'net_cents': 80,
          'status': 'weird',
        }),
      ],
    );
    await tester.pumpWidget(app(port));
    await tester.pumpAndSettle();
    expect(find.text(settlementLineStatusLabel(SettlementLineStatus.unknown)),
        findsOneWidget);
  });
}
