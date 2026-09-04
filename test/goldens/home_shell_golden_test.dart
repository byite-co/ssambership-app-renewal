import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/home_shell.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;

import 'golden_app_fakes.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 홈 셸(하단 5탭 + AppBar 프로필 버튼) — 학생 로그인, 시작 탭 = 질문방(학생 목록).
/// A-1 에서는 AuthService·NotificationBadgeController 싱글턴 때문에 만들지 않았던 골든.
/// 알림 배지는 '없음' fake(count null → 숨김), 탈퇴 배너는 잡 없음 fake.
void main() {
  testWidgets('golden: home_shell_student', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      const HomeShell(),
      role: AppRole.student,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.student, userId: kStudentId),
        questionRoomRead: GoldenReadRepository(
          roomRows: goldenStudentRooms(),
          statusRows: goldenStudentStatusRows(),
          usageByMentor: goldenUsageByMentor(),
        ),
        mentorLookup: GoldenMentorLookup(goldenMentors()),
        subscriptions: GoldenSubscriptions(goldenSubscriptionsByMentor()),
      ),
    );
    expect(find.text(kMentorName), findsOneWidget);
    await expectScreenGolden(tester, 'home_shell_student');
  });
}
