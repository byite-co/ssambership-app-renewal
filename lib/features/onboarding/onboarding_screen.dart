import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_route_paths.dart';
import '../../design/tokens/app_spacing.dart';
import '../../design/tokens/app_typography.dart';
import '../../design/widgets/app_background.dart';
import '../../design/widgets/app_primary_button.dart';
import '../../shared/constants/app_constants.dart';
import '../dev/dev_flags.dart';

/// 온보딩(자리). 진입 → 로그인으로 넘어가는 골격만.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(AppConstants.appDisplayName,
                      style: AppTypography.title),
                  const SizedBox(height: 8),
                  const Text('질문 멘토링, 모바일에서',
                      style: AppTypography.captionSecondary),
                  const SizedBox(height: 28),
                  AppPrimaryButton(
                    label: '시작하기',
                    expand: false,
                    onPressed: () => context.go(AppRoutePaths.login),
                  ),
                  // ★ 개발 전용 진입 — 출시 빌드에서는 노출되지 않는다.
                  if (kDevToolsEnabled) ...<Widget>[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.go(AppRoutePaths.devGallery),
                      child: const Text('위젯 갤러리 (개발용)'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
