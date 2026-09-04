import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/ui/mentor/student_room_home_screen.dart';

import 'golden_app_fakes.dart';
import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 멘토 질문방 2뎁스(학생방 홈) — 답변 대기 건수·최근 질문·연결노트 미리보기·구독 상태.
/// 레포지토리·구독 리더·사용자 id 를 AppScope 로 주입(A-2).
void main() {
  testWidgets('golden: student_room_home', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      StudentRoomHomeScreen(room: goldenRoom(), studentName: kStudentName),
      role: AppRole.mentor,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.mentor, userId: kMentorId),
        questionRoomRead: GoldenReadRepository(
          threadRows: goldenThreads(),
          noteRows: goldenNotes(),
        ),
        subscriptions: GoldenSubscriptions(goldenSubscriptionsByMentor()),
      ),
    );
    expect(find.text(kStudentName), findsWidgets);
    await expectScreenGolden(tester, 'student_room_home');
  });
}
