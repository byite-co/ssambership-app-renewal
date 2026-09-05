import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/question_room_screen.dart';

import 'golden_app_fakes.dart';
import 'golden_harness.dart';

/// 질문방 탭 1뎁스(QuestionRoomScreen) — guest 빈 상태 골든.
///
/// A-1: 이 위젯이 AuthService.instance 로 역할을 분기해 테스트에서 학생 목록을 그릴 수
/// 없다는 사실을 고정했다. A-2 에서 역할·레포지토리는 AppScope 로 주입되며 실제 학생
/// 목록 골든은 student_room_list_golden_test.dart 가 맡는다.
///
/// 이 골든은 명시적 guest AppScope로 종전의 '학생·멘토 전용' 빈 상태를 고정한다.
void main() {
  testWidgets('golden: question_room_tab_singleton_fallback',
      (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      const QuestionRoomScreen(),
      role: AppRole.student,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(role: AppRole.guest, guest: true),
      ),
    );
    // 명시적 guest 역할 → 학생 목록 대신 빈 상태(종전과 동일).
    expect(find.text('질문방은 학생·멘토 전용이에요'), findsOneWidget);
    await expectScreenGolden(tester, 'question_room_tab_singleton_fallback');
  });
}
