import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart';
import '../core/version_gate/version_gate_controller.dart';
import '../core/version_gate/version_gate_shell.dart';
import '../design/theme.dart';
import '../shared/constants/app_constants.dart';
import 'router.dart';

/// 루트 앱: 테마 + 라우터.
///
/// 테마는 현재 로그인 역할(AuthService.currentRole)에 따라 강조색이 분기된다
/// (학생/공개=파랑, 멘토=초록). role 변화(로그인/로그아웃) 시 테마가 재빌드된다.
class SsambershipApp extends StatelessWidget {
  const SsambershipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthService.instance,
      builder: (BuildContext context, Widget? _) {
        return MaterialApp.router(
          title: AppConstants.appDisplayName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(AuthService.instance.currentRole),
          routerConfig: AppRouter.router,
          // 최소 지원 버전 게이트 — 라우터(Navigator) '위'에 얹는다.
          // 통과 전에는 어떤 라우트(로그인 전·후 무관)로도 들어갈 수 없다.
          // 검사 시작은 main() 이 runApp 직전에 한다(VersionGateController.start).
          builder: (BuildContext context, Widget? child) => VersionGateShell(
            controller: VersionGateController.instance,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
