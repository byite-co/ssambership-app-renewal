import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../core/version_gate/version_gate_shell.dart';
import '../design/theme.dart';
import '../shared/constants/app_constants.dart';
import 'app_scope.dart';
import 'router.dart';

/// 루트 앱: 의존성 스코프 + 테마 + 라우터.
///
/// main() 이 만든 [AppDependencies] 를 [AppScope] 로 트리 전체에 내려보낸다(A-2).
/// 테마는 현재 로그인 역할(auth.currentRole)에 따라 강조색이 분기된다
/// (학생/공개=파랑, 멘토=초록). role 변화(로그인/로그아웃) 시 테마가 재빌드된다.
class SsambershipApp extends StatefulWidget {
  const SsambershipApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<SsambershipApp> createState() => _SsambershipAppState();
}

class _SsambershipAppState extends State<SsambershipApp> {
  late GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppRouter.create(widget.dependencies);
  }

  @override
  void didUpdateWidget(covariant SsambershipApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dependencies, widget.dependencies)) {
      _router.dispose();
      _router = AppRouter.create(widget.dependencies);
    }
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppDependencies dependencies = widget.dependencies;
    return AppScope(
      dependencies: dependencies,
      child: ListenableBuilder(
        listenable: dependencies.auth,
        builder: (BuildContext context, Widget? _) {
          return MaterialApp.router(
            title: AppConstants.appDisplayName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(dependencies.auth.currentRole),
            // G5: 한국어 단일 앱 — 시스템 위젯 문자열(날짜 선택기·텍스트 메뉴 등)도
            // 한국어로 고정한다. 기기 언어와 무관하게 ko 하나만 지원.
            locale: const Locale('ko'),
            supportedLocales: const <Locale>[Locale('ko')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: _router,
            // 최소 지원 버전 게이트 — 라우터(Navigator) '위'에 얹는다.
            // 통과 전에는 어떤 라우트(로그인 전·후 무관)로도 들어갈 수 없다.
            // 검사 시작은 main() 이 runApp 직전에 한다(VersionGateController.start).
            builder: (BuildContext context, Widget? child) => VersionGateShell(
              controller: dependencies.versionGate,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
    );
  }
}
