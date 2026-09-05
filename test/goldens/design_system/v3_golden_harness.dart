import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/design/app_theme.dart';
import 'package:ssambership_app/design/role_theme.dart';
import 'package:ssambership_app/design/widgets/app_background.dart';

const Size kV3GoldenLogicalSize = Size(390, 844);
const double kV3GoldenDevicePixelRatio = 2;

Future<void> pumpV3Golden(
  WidgetTester tester,
  Widget child, {
  AppRole role = AppRole.student,
}) async {
  tester.view.physicalSize = kV3GoldenLogicalSize * kV3GoldenDevicePixelRatio;
  tester.view.devicePixelRatio = kV3GoldenDevicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: RoleTheme(
        role: role,
        child: AppBackground(child: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> expectV3Golden(WidgetTester tester, String name) {
  return expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('images/$name.png'),
  );
}
