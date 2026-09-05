import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/mypage/mypage_screen.dart';
import 'package:ssambership_app/shared/constants/app_constants.dart';

import '../support/fake_mentor_console.dart';
import 'golden_app_fakes.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 마이페이지 **로그인 상태** 변형(학생·멘토). A-1 의 mypage_student/mypage_mentor 는
/// 싱글턴 폴백 때문에 로그아웃 상태로만 그려졌다 — A-2 에서 auth 를 주입해 두 벌을 갖춘다.
/// 데이터도 loaderOverride 가 아니라 AppScope 의 마이페이지 레포(fake)로 읽는다.
void main() {
  Widget page() => Scaffold(
        appBar: AppBar(title: const Text(AppConstants.myPageTitle)),
        body: MyPageScreen(
          onOpenQuestionsTab: () {},
          onOpenNotifications: () {},
        ),
      );

  testWidgets('golden: mypage_student_signed_in', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      page(),
      role: AppRole.student,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.student, userId: kStudentId),
        myPage: GoldenMyPageRepository(goldenStudentMyPage()),
      ),
    );
    // 로그인 상태 증거 = 프로필 수정 아이콘(세션 있을 때만 노출). 로그아웃 버튼은
    // 학생 페이지에선 뷰포트 아래(구독·캐시 섹션 뒤)라 여기서 단언하지 않는다.
    expect(find.byTooltip('프로필 수정'), findsOneWidget);
    await expectScreenGolden(tester, 'mypage_student_signed_in');
  });

  testWidgets('golden: mypage_mentor_signed_in', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      page(),
      role: AppRole.mentor,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.mentor, userId: kMentorId),
        myPage: GoldenMyPageRepository(goldenMentorMyPage()),
        mentorConsole: FakeMentorConsole(profile: goldenMentorOwnProfile()),
      ),
    );
    expect(find.byTooltip('프로필 수정'), findsOneWidget);
    // A-4b ④⑦: 활동 상태·학생증 섹션이 들어와 로그아웃 버튼은 뷰포트 아래로 내려갔다
    // (학생 변형과 같은 이유로 여기서 단언하지 않는다). 섹션 노출로 대신 확인.
    expect(find.text('활동 상태'), findsOneWidget);
    await expectScreenGolden(tester, 'mypage_mentor_signed_in');
  });
}
