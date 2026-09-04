import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/question_room/question_room_screen.dart';

import 'golden_harness.dart';

/// 질문방 탭 1뎁스(QuestionRoomScreen) — **골격 결합 기록용 골든**.
///
/// 이 위젯은 AuthService.instance.currentRole 로 학생/멘토 화면을 고르고,
/// 학생 목록(_StudentRoomList)은 const QuestionRoomReadRepository() 와
/// SupabaseInit.clientOrNull 을 직접 읽는다(주입 seam 없음). 테스트 환경에서는
/// 싱글턴이 기본값(guest)이라 학생 목록이 아니라 '학생·멘토 전용' 빈 상태가
/// 그려진다. 즉 이 골든은 **대표 화면을 렌더하지 못한다는 사실 자체**를 고정한다.
/// A-2/A-3(라우팅·DI 교체) 뒤에 이 테스트는 실제 학생 목록 골든으로 교체돼야 한다.
void main() {
  testWidgets('golden: question_room_tab_singleton_fallback',
      (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      const QuestionRoomScreen(),
      role: AppRole.student,
    );
    // 싱글턴 기본값(guest) 때문에 학생 목록 대신 빈 상태가 나온다 — 결합의 증거.
    expect(find.text('질문방은 학생·멘토 전용이에요'), findsOneWidget);
    await expectScreenGolden(tester, 'question_room_tab_singleton_fallback');
  });
}
