import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart';
import 'package:ssambership_app/core/web_bridge/web_bridge_config.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/mypage_screen.dart';
import 'package:ssambership_app/features/mypage/ui/sections/support_section.dart';

/// 리뷰 메뉴 역할 게이트 — 범용 '리뷰 작성' 행 폐기, 멘토에게만 '받은 리뷰'.
/// 목적지는 웹 멘토 받은 리뷰 화면 계약(/mentor/reviews)과 일치해야 한다.

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('기본(학생·게스트·관리자): 리뷰 행 미노출 — 리뷰 작성도 받은 리뷰도 없음',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const SupportSection()));
    expect(find.text('리뷰 작성'), findsNothing);
    expect(find.text('받은 리뷰'), findsNothing);
    expect(find.text('알림'), findsOneWidget); // 나머지 행 유지
    expect(find.text('고객지원'), findsOneWidget);
  });

  testWidgets('멘토: 받은 리뷰 행 노출(라벨은 받은 리뷰 — 리뷰 작성 아님)',
      (WidgetTester tester) async {
    await tester
        .pumpWidget(_wrap(const SupportSection(showReceivedReviews: true)));
    expect(find.text('받은 리뷰'), findsOneWidget);
    expect(find.text('리뷰 작성'), findsNothing);
  });

  test('목적지 계약: 웹 멘토 받은 리뷰 경로(/mentor/reviews) 고정', () {
    expect(WebBridgeConfig.reviewsPath, '/mentor/reviews');
  });

  testWidgets('역할 배선: 학생 마이페이지엔 리뷰 행 없음', (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MyPageScreen(
          loaderOverride: () async => const MyPageData(
            role: AppRole.student,
            profile: MyProfile(name: '학생', roleLabel: '학생'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('리뷰 작성'), findsNothing);
    expect(find.text('받은 리뷰'), findsNothing);
  });

  testWidgets('역할 배선: 멘토 마이페이지엔 받은 리뷰 노출', (WidgetTester tester) async {
    _bigSurface(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MyPageScreen(
          loaderOverride: () async => const MyPageData(
            role: AppRole.mentor,
            profile: MyProfile(name: '멘토', roleLabel: '멘토'),
            mentor: MentorDashboard(
              studentCount: 0,
              pendingAnswers: 0,
              latestSettlementCents: 0,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('받은 리뷰'), findsOneWidget);
    expect(find.text('리뷰 작성'), findsNothing);
  });
}
