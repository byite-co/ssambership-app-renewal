import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/app_route_paths.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/auth/login_screen.dart';

import 'golden_app_fakes.dart';
import 'golden_harness.dart';

void main() {
  testWidgets('golden: login_student', (WidgetTester tester) async {
    final FakeAppAuth auth = FakeAppAuth(role: AppRole.student);
    await pumpGoldenRoute(
      tester,
      routePath: AppRoutePaths.login,
      screen: const LoginScreen(),
      role: AppRole.student,
      dependencies: goldenDependencies(auth: auth),
    );

    expect(find.text('이메일'), findsOneWidget);
    expect(find.text('둘러보기'), findsOneWidget);
    await expectScreenGolden(tester, 'login_student');
  });

  testWidgets('golden: login_mentor', (WidgetTester tester) async {
    final FakeAppAuth auth = FakeAppAuth(role: AppRole.mentor);
    await pumpGoldenRoute(
      tester,
      routePath: AppRoutePaths.login,
      screen: const LoginScreen(),
      role: AppRole.mentor,
      dependencies: goldenDependencies(auth: auth),
    );

    expect(find.text('이메일'), findsOneWidget);
    expect(find.text('둘러보기'), findsOneWidget);
    await expectScreenGolden(tester, 'login_mentor');
  });
}
