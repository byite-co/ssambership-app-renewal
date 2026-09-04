import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';

import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 질문 대화(학생 채팅) — 학생 질문 2·멘토 답변 1, 답변완료 상태칩, 입력바.
void main() {
  testWidgets('golden: student_chat', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      ChatScreen(
        thread: goldenThread(
          id: 't3',
          status: ThreadStatus.answered,
          title: '삼각함수 합성 문제에서 위상 구하는 법',
          subject: 'math_1',
          day: 3,
        ),
        mentorName: kMentorName,
        room: goldenRoom(),
        currentUserIdOverride: kStudentId,
        readRepository: GoldenReadRepository(messageRows: goldenMessages('t3')),
        realtimeFactory: (String _) => GoldenNoopRealtime(),
        safety: const GoldenSafety(),
        uploader: const GoldenUploader(),
      ),
      role: AppRole.student,
    );
    await expectScreenGolden(tester, 'student_chat');
  });
}
