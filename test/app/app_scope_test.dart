import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/app_scope.dart';

import '../support/app_scope_test_harness.dart';

void main() {
  testWidgets('AppScope.of throws an identifiable error when scope is absent',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            AppScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final Object? exception = tester.takeException();
    expect(exception, isA<FlutterError>());
    expect(
      exception.toString(),
      contains('does not contain an AppScope'),
    );
  });

  testWidgets('AppScope.of returns the identical injected dependencies',
      (WidgetTester tester) async {
    final AppDependencies dependencies =
        testAppDependencies(auth: TestAppAuth());
    AppDependencies? resolved;

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              resolved = AppScope.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(resolved, same(dependencies));
  });
}
