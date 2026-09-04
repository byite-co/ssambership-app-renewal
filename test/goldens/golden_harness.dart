import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/design/theme.dart';

/// 골든 뷰포트 — 세로 390×844 논리 픽셀(현행 스마트폰 표준 폭), 2배율 렌더.
/// 모든 골든이 같은 프레임을 쓰므로 화면 간 비교가 가능하다.
const Size kGoldenLogicalSize = Size(390, 844);
const double kGoldenDevicePixelRatio = 2.0;

/// 화면 위젯을 **실제 앱과 같은 껍데기**(AppTheme·Pretendard·ko 로케일)로 감싸
/// 고정 뷰포트에 렌더한다. 네트워크·전역 싱글턴에 닿지 않는 픽스처만 넘길 것.
Future<void> pumpGoldenScreen(
  WidgetTester tester,
  Widget screen, {
  AppRole role = AppRole.student,
  Size logicalSize = kGoldenLogicalSize,
  double devicePixelRatio = kGoldenDevicePixelRatio,
}) async {
  tester.view.physicalSize = logicalSize * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(role),
      locale: const Locale('ko'),
      supportedLocales: const <Locale>[Locale('ko')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
}

/// 현재 프레임 전체를 `test/goldens/images/<name>.png` 와 비교한다.
/// 기준 이미지 갱신: `flutter test test/goldens --update-goldens`
Future<void> expectScreenGolden(WidgetTester tester, String name) {
  return expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('images/$name.png'),
  );
}
