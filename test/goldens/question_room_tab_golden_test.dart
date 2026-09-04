import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/question_room_screen.dart';

import 'golden_harness.dart';

/// 질문방 탭 1뎁스(QuestionRoomScreen) — **AppScope 폴백 기록용 골든**.
///
/// A-1: 이 위젯이 AuthService.instance 로 역할을 분기해 테스트에서 학생 목록을 그릴 수
/// 없다는 사실을 고정했다. A-2 에서 역할·레포지토리는 AppScope 로 주입되며 실제 학생
/// 목록 골든은 student_room_list_golden_test.dart 가 맡는다.
///
/// 이 골든은 남겨 둔다 — **AppScope 가 없을 때** `AppScope.of` 가 운영 싱글턴으로
/// 폴백해 종전과 똑같이(싱글턴 기본 역할 guest → '학생·멘토 전용' 빈 상태) 동작함을
/// 고정한다. 기존 위젯 테스트 1,500여 건이 이 호환성 위에서 무수정 통과한다.
/// A-3 에서 폴백을 제거할 때 이 테스트도 함께 정리한다.
void main() {
  testWidgets('golden: question_room_tab_singleton_fallback',
      (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      const QuestionRoomScreen(),
      role: AppRole.student,
      withScope: false, // AppScope 없음 → 운영 폴백(싱글턴) 경로.
    );
    // 폴백 싱글턴의 기본 역할(guest) → 학생 목록 대신 빈 상태(종전과 동일).
    expect(find.text('질문방은 학생·멘토 전용이에요'), findsOneWidget);
    await expectScreenGolden(tester, 'question_room_tab_singleton_fallback');
  });
}
