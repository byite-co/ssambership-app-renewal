import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/app_scope.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/design/theme.dart';

import 'golden_app_fakes.dart';

/// 골든 뷰포트 — 세로 390×844 논리 픽셀(현행 스마트폰 표준 폭), 2배율 렌더.
/// 모든 골든이 같은 프레임을 쓰므로 화면 간 비교가 가능하다.
const Size kGoldenLogicalSize = Size(390, 844);
const double kGoldenDevicePixelRatio = 2.0;

/// 화면 위젯을 **실제 앱과 같은 껍데기**(AppScope·AppTheme·Pretendard·ko 로케일)로
/// 감싸 고정 뷰포트에 렌더한다. 네트워크·전역 싱글턴에 닿지 않는 픽스처만 넘길 것.
///
/// - [dependencies]: AppScope 에 실을 의존성. 생략하면 [role] 의 fake 인증(세션 없음)
///   + '없음' fake 컨트롤러로 채운 [goldenDependencies].
/// - [withScope]=false 면 AppScope 없이 렌더한다 — AppScope.of 의 운영 폴백(종전
///   싱글턴 동작)을 확인하는 골든 전용.
Future<void> pumpGoldenScreen(
  WidgetTester tester,
  Widget screen, {
  AppRole role = AppRole.student,
  Size logicalSize = kGoldenLogicalSize,
  double devicePixelRatio = kGoldenDevicePixelRatio,
  AppDependencies? dependencies,
  bool withScope = true,
}) async {
  tester.view.physicalSize = logicalSize * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final Widget app = MaterialApp(
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
  );
  await tester.pumpWidget(
    withScope
        ? AppScope(
            dependencies:
                dependencies ?? goldenDependencies(auth: FakeAppAuth(role: role)),
            child: app,
          )
        : app,
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
