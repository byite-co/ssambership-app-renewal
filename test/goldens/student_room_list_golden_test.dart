import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/question_room_screen.dart';

import 'golden_app_fakes.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 학생 질문방 목록(1뎁스, 질문방 탭 본문) — A-1 에서 렌더 불가였던 화면.
/// 역할·사용자 id·레포지토리를 AppScope 로 주입해 그린다(A-2).
/// HomeShell 이 앱바·탭바를 제공하므로 같은 껍데기([goldenTabFrame])로 감싼다.
void main() {
  testWidgets('golden: student_room_list', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      goldenTabFrame(
        role: AppRole.student,
        selectedIndex: 0,
        child: const QuestionRoomScreen(),
      ),
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
    await expectScreenGolden(tester, 'student_room_list');
  });
}
