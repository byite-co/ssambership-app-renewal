import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/home_shell.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/community/community_screen.dart';
import 'package:ssambership_app/features/individual_question/ui/mentor_iq_list_screen.dart';
import 'package:ssambership_app/features/individual_question/ui/student_iq_list_screen.dart';
import 'package:ssambership_app/features/mentors/mentors_screen.dart';
import 'package:ssambership_app/features/notifications/data/notification_badge_controller.dart';
import 'package:ssambership_app/features/notifications/notifications_screen.dart';

import 'golden_app_fakes.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';
import 'tab_entry_golden_fakes.dart';

/// A-2의 student_room_list·mentor_inbox 두 장이 각 역할의 질문방 진입 화면을
/// 이미 고정한다. 이 파일은 나머지 8개(역할별 4개)를 채워 5×2 표면을 완성한다.
void main() {
  // 탭 본문은 홈 셸과 같은 껍데기(배경·유리 앱바·유리 탭바)로 그린다.
  Widget frame(AppRole role, int index, Widget child) =>
      goldenTabFrame(role: role, selectedIndex: index, child: child);

  testWidgets('golden: student_iq_tab', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      frame(AppRole.student, 1,
        StudentIqListScreen(
          embedded: true,
          loaderOverride: () async => goldenStudentIndividualQuestions(),
          repositoryOverride: const GoldenIndividualQuestions(),
        ),
      ),
      role: AppRole.student,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.student, userId: kStudentId),
      ),
    );

    expect(find.text('미적분 극한 풀이를 확인해 주세요'), findsOneWidget);
    await expectScreenGolden(tester, 'student_iq_tab');
  });

  testWidgets('golden: student_mentors_tab', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      frame(AppRole.student, 2,
        MentorsScreen(
          directory: GoldenMentorDirectory(goldenMentorDirectoryItems()),
          favorites: const GoldenMentorFavorites(
            ids: <String>{kMentorId},
          ),
        ),
      ),
      role: AppRole.student,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.student, userId: kStudentId),
      ),
    );

    expect(find.text(kMentorName), findsOneWidget);
    expect(find.text('찜한 멘토 1'), findsOneWidget);
    await expectScreenGolden(tester, 'student_mentors_tab');
  });

  testWidgets('golden: student_community_tab', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      frame(AppRole.student, 3,
        CommunityScreen(
          read: GoldenCommunityRead(
            boardsList: goldenBoards(),
            shortformsList: goldenShortforms(),
          ),
          write: const GoldenCommunityWrite(),
        ),
      ),
      role: AppRole.student,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.student, userId: kStudentId),
      ),
    );

    expect(find.text('오답노트, 이렇게 복습해 보세요'), findsOneWidget);
    expect(find.text('숏폼 작성'), findsNothing);
    await expectScreenGolden(tester, 'student_community_tab');
  });

  testWidgets('golden: student_notifications_tab', (WidgetTester tester) async {
    final GoldenNotifications notifications = GoldenNotifications(
      goldenTabNotifications(),
    );
    await pumpGoldenScreen(
      tester,
      frame(AppRole.student, 4,
        NotificationsScreen(
          repository: notifications,
          badge: NotificationBadgeController(repository: notifications),
          realtimeFactory: (_) => GoldenNotificationsRealtime(),
        ),
      ),
      role: AppRole.student,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.student, userId: kStudentId),
      ),
    );

    expect(find.text('답변이 도착했어요'), findsOneWidget);
    expect(find.text('모두 읽음'), findsOneWidget);
    await expectScreenGolden(tester, 'student_notifications_tab');
  });

  testWidgets('golden: mentor_iq_tab', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      frame(AppRole.mentor, 1,
        MentorIqListScreen(
          embedded: true,
          loaderOverride: () async => MentorIqListData(
            open: goldenOpenIndividualQuestions(),
            mine: goldenMentorIndividualQuestions(),
          ),
          repositoryOverride: const GoldenIndividualQuestions(),
        ),
      ),
      role: AppRole.mentor,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.mentor, userId: kMentorId),
      ),
    );

    expect(find.text('수락 대기 (공개형)'), findsOneWidget);
    expect(find.text('기하 벡터 내적 풀이 질문'), findsOneWidget);
    await expectScreenGolden(tester, 'mentor_iq_tab');
  });

  testWidgets('golden: mentor_settlements_tab', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      frame(AppRole.mentor, 2,
        const MentorSettlementsTabBody(),
      ),
      role: AppRole.mentor,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.mentor, userId: kMentorId),
        myPage: GoldenMyPageRepository(goldenMentorMyPage()),
      ),
    );

    expect(find.text('답변 대기'), findsOneWidget);
    expect(find.text('최근 정산'), findsOneWidget);
    await expectScreenGolden(tester, 'mentor_settlements_tab');
  });

  testWidgets('golden: mentor_community_tab', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      frame(AppRole.mentor, 3,
        CommunityScreen(
          read: GoldenCommunityRead(
            boardsList: goldenBoards(),
            shortformsList: goldenShortforms(),
          ),
          write: const GoldenCommunityWrite(),
        ),
      ),
      role: AppRole.mentor,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.mentor, userId: kMentorId),
      ),
    );

    expect(find.text('오답노트, 이렇게 복습해 보세요'), findsOneWidget);
    expect(find.text('숏폼 작성'), findsOneWidget);
    await expectScreenGolden(tester, 'mentor_community_tab');
  });

  testWidgets('golden: mentor_notifications_tab', (WidgetTester tester) async {
    final GoldenNotifications notifications = GoldenNotifications(
      goldenTabNotifications(),
    );
    await pumpGoldenScreen(
      tester,
      frame(AppRole.mentor, 4,
        NotificationsScreen(
          repository: notifications,
          badge: NotificationBadgeController(repository: notifications),
          realtimeFactory: (_) => GoldenNotificationsRealtime(),
        ),
      ),
      role: AppRole.mentor,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.mentor, userId: kMentorId),
      ),
    );

    expect(find.text('답변이 도착했어요'), findsOneWidget);
    expect(find.text('모두 읽음'), findsOneWidget);
    await expectScreenGolden(tester, 'mentor_notifications_tab');
  });
}
