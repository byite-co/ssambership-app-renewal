import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/ui/mentor/mentor_answer_screen.dart';

import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 멘토 답변 화면 — 같은 대화를 멘토 시점(내 말풍선 = 답변)으로, 멘토 강조색 테마.
void main() {
  testWidgets('golden: mentor_answer', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      MentorAnswerScreen(
        thread: goldenThread(
          id: 't3',
          status: ThreadStatus.answered,
          title: '삼각함수 합성 문제에서 위상 구하는 법',
          subject: 'math_1',
          day: 3,
        ),
        studentName: kStudentName,
        room: goldenRoom(),
        currentUserIdOverride: kMentorId,
        readRepository: GoldenReadRepository(messageRows: goldenMessages('t3')),
        realtimeFactory: (String _) => GoldenNoopRealtime(),
        safety: const GoldenSafety(),
        uploader: const GoldenUploader(),
      ),
      role: AppRole.mentor,
    );
    await expectScreenGolden(tester, 'mentor_answer');
  });
}
