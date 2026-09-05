import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import '../core/version_gate/version_gate_shell.dart';
import '../design/role_theme.dart';
import '../shared/constants/app_constants.dart';
import 'app_chrome.dart';
import 'app_scope.dart';
import 'router.dart';

/// 루트 앱: 의존성 스코프 + 역할 컨텍스트 + v3 테마 + 배경 + 라우터.
///
/// main() 이 만든 [AppDependencies] 를 [AppScope] 로 트리 전체에 내려보낸다(A-2).
/// 역할색은 현재 로그인 역할(auth.currentRole)로 정해 [RoleTheme] 으로 내려보내고
/// (학생/공개=파랑, 멘토=초록), 테마도 같은 역할로 빌드한다. role 변화(로그인/
/// 로그아웃) 시 둘 다 재빌드된다. 배경 그라디언트는 `builder:` 에서 라우터 아래에
/// 한 번 깐다(A-6b).
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
          final AppRole role = themeRoleOf(dependencies.auth.currentRole);
          return appChrome(
            role: role,
            child: (ThemeData theme) => MaterialApp.router(
              title: AppConstants.appDisplayName,
              debugShowCheckedModeBanner: false,
              theme: theme,
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
              // 배경 그라디언트는 게이트 화면과 라우터 화면이 같이 쓴다.
              builder: (BuildContext context, Widget? child) =>
                  appBackgroundBuilder(
                context,
                VersionGateShell(
                  controller: dependencies.versionGate,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
