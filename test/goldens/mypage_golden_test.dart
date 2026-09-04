import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/mypage_screen.dart';
import 'package:ssambership_app/shared/constants/app_constants.dart';

import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 마이페이지(학생·멘토). MyPageScreen 은 본문만 그리므로 HomeShell 의
/// _MyPagePage 와 같은 Scaffold+AppBar 로 감싼다.
///
/// ★ 결합 기록: 화면 안의 '프로필 수정'·'로그아웃' 노출은 AuthService.instance.isSignedIn
///   (테스트에선 항상 false)을 직접 읽는다. 따라서 이 골든은 **로그아웃 상태 변형**이며,
///   실제 로그인 화면과 그 두 요소가 다를 수 있다 — A-3(DI) 입력.
void main() {
  Widget page(MyPageData Function() data) => Scaffold(
        appBar: AppBar(title: const Text(AppConstants.myPageTitle)),
        body: MyPageScreen(
          loaderOverride: () async => data(),
          onOpenQuestionsTab: () {},
          onOpenNotifications: () {},
        ),
      );

  testWidgets('golden: mypage_student', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      page(goldenStudentMyPage),
      role: AppRole.student,
    );
    await expectScreenGolden(tester, 'mypage_student');
  });

  testWidgets('golden: mypage_mentor', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      page(goldenMentorMyPage),
      role: AppRole.mentor,
    );
    await expectScreenGolden(tester, 'mypage_mentor');
  });
}
