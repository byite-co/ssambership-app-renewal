import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/ui/question_list_screen.dart';

import 'golden_fixtures.dart';
import 'golden_harness.dart';

/// 학생 질문 목록(질문 영역, 멘토방 안 3뎁스) — 대기·답변완료·확인완료 스레드 3장.
///
/// ★ 대표 화면 "학생 질문방 목록"의 1뎁스(QuestionRoomScreen → _StudentRoomList)는
///   AuthService.instance(역할 분기)와 const QuestionRoomReadRepository()(주입 불가)
///   에 직접 묶여 있어 픽스처로 렌더할 수 없다 — question_room_tab_golden_test.dart
///   와 docs/renewal/bootstrap-report 에 기록. 여기서는 주입 seam 이 있는 가장
///   가까운 화면(QuestionListScreen)을 기준선으로 잡는다.
void main() {
  testWidgets('golden: student_question_list', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      QuestionListScreen(
        room: goldenRoom(),
        mentorName: kMentorName,
        sub: goldenSubscription(),
        readRepository: GoldenReadRepository(
          threadRows: goldenThreads(),
          usage: goldenUsage,
        ),
      ),
      role: AppRole.student,
    );
    await expectScreenGolden(tester, 'student_question_list');
  });
}
