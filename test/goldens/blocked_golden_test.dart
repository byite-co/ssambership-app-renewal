import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/account_status.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/auth/blocked_screen.dart';

import 'golden_app_fakes.dart';
import 'golden_harness.dart';

/// 차단 화면 — '일시 조회 실패'(재시도 가능) 변형: 재시도·로그아웃 두 버튼이 모두 보인다.
/// 인증 상태는 AppScope 의 fake 로 주입(A-2).
void main() {
  testWidgets('golden: blocked_retryable', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      const BlockedScreen(),
      role: AppRole.student,
      dependencies: goldenDependencies(
        auth: FakeAppAuth(
          role: AppRole.student,
          userId: 's1',
          account: AccountState.fetchFailed,
        ),
      ),
    );
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
    await expectScreenGolden(tester, 'blocked_retryable');
  });
}
