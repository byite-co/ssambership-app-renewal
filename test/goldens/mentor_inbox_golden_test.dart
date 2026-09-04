import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/question_room_screen.dart';
import 'package:ssambership_app/shared/constants/app_constants.dart';

import 'golden_app_fakes.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 멘토 인박스(질문방 탭 본문, 멘토 역할) — A-1 에서 렌더 불가였던 화면.
/// QuestionRoomScreen 이 주입된 역할(mentor)로 MentorInboxScreen 을 고른다.
void main() {
  testWidgets('golden: mentor_inbox', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      Scaffold(
        appBar: AppBar(title: Text(AppConstants.bottomTabLabels[0])),
        body: const QuestionRoomScreen(),
      ),
      role: AppRole.mentor,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.mentor, userId: kMentorId),
        questionRoomRead: GoldenReadRepository(
          roomRows: goldenMentorRooms(),
          statusRows: goldenMentorStatusRows(),
        ),
        studentLookup: GoldenStudentLookup(goldenStudents()),
      ),
    );
    expect(find.text(kStudentName), findsOneWidget);
    await expectScreenGolden(tester, 'mentor_inbox');
  });
}
