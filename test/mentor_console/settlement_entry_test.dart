import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/home_shell.dart';
import 'package:ssambership_app/app/routes/mypage_routes.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mentor_console/ui/mentor_settlement_screen.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';

import '../goldens/golden_app_fakes.dart' show GoldenMyPageRepository;
import '../support/app_scope_test_harness.dart';
import '../support/fake_mentor_console.dart';
import '../support/mentor_console_fixtures.dart';

/// A-4a 정산 허브 진입점 — 정산 탭(멘토)·마이페이지(멘토) AppBar 아이콘.
/// 탭 본문·마이페이지 본문은 골든 고정이라 손대지 않고 AppBar 액션으로만 연다.
void main() {
  MyPageData mentorData() => const MyPageData(
        role: AppRole.mentor,
        profile: MyProfile(name: '탐색멘토', roleLabel: '멘토'),
        mentor: MentorDashboard(
          studentCount: 1,
          pendingAnswers: 0,
          latestSettlementCents: 0,
        ),
      );

  MyPageData studentData() => const MyPageData(
        role: AppRole.student,
        profile: MyProfile(name: '탐색학생', roleLabel: '학생', grade: '고2'),
      );

  Widget scoped(Widget home, AppRole role, MyPageData data) =>
      withTestAppScope(
        MaterialApp(home: home),
        dependencies: testAppDependencies(
          auth: TestAppAuth(role: role, userId: 'u1'),
          mentorConsole: FakeMentorConsole(
            summary: sampleSettlementSummary(),
            lines: sampleSettlementLines(),
          ),
          myPage: GoldenMyPageRepository(data),
        ),
      );

  testWidgets('멘토 정산 탭: AppBar 아이콘 → 정산 허브(/settlements/history)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(scoped(
      HomeShell(myPageLoaderOverride: () async => mentorData()),
      AppRole.mentor,
      mentorData(),
    ));
    await tester.pumpAndSettle();

    // 질문방 탭에서는 없다.
    expect(find.byTooltip(MentorSettlementScreen.entryTooltip), findsNothing);

    await tester.tap(find.text('정산'));
    await tester.pumpAndSettle();
    expect(find.text('답변 · 정산 요약'), findsOneWidget); // 기존 탭 본문 유지.
    expect(find.byTooltip(MentorSettlementScreen.entryTooltip), findsOneWidget);

    await tester.tap(find.byTooltip(MentorSettlementScreen.entryTooltip));
    await tester.pumpAndSettle();
    expect(find.text('2026년 9월 받을 금액'), findsOneWidget);
    expect(find.text('431,200원'), findsOneWidget);
  });

  testWidgets('학생 HomeShell 에는 정산 허브 아이콘이 없다', (WidgetTester tester) async {
    await tester.pumpWidget(scoped(
      HomeShell(myPageLoaderOverride: () async => studentData()),
      AppRole.student,
      studentData(),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip(MentorSettlementScreen.entryTooltip), findsNothing);
    await tester.tap(find.text('알림'));
    await tester.pumpAndSettle();
    expect(find.byTooltip(MentorSettlementScreen.entryTooltip), findsNothing);
  });

  testWidgets('마이페이지(멘토): AppBar 아이콘 → 정산 허브 / 학생은 없음', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(scoped(
      MyPageRoutePage(loaderOverride: () async => mentorData()),
      AppRole.mentor,
      mentorData(),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip(MentorSettlementScreen.entryTooltip), findsOneWidget);
    await tester.tap(find.byTooltip(MentorSettlementScreen.entryTooltip));
    await tester.pumpAndSettle();
    expect(find.text('431,200원'), findsOneWidget);

    await tester.pumpWidget(scoped(
      MyPageRoutePage(loaderOverride: () async => studentData()),
      AppRole.student,
      studentData(),
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip(MentorSettlementScreen.entryTooltip), findsNothing);
  });
}
