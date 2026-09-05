import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// 배지 톤. [role] 은 현재 역할색 틴트(기본), [info] 는 역할과 무관한 파랑
/// (진행 중 — 멘토 화면에서도 성공 초록과 구분돼야 한다), 나머지는 상태색.
enum AppBadgeTone { role, neutral, info, success, warning, danger }

/// v3 배지(design-v3 §0 '상태 배지') — 모서리 6 · 13 SemiBold · 옅은 틴트 채움.
/// 한글 라벨만 받는다(영문 코드값 노출 금지 — 호출부에서 매핑).
///
/// A-6a 의 역할 틴트 배지를 정본으로 하고, 옛 `AppBadge(tinted:)` 를 흡수했다:
/// [tinted] 가 주어지면 `true` = [AppBadgeTone.role], `false` = [AppBadgeTone.neutral].
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.role,
    this.tinted,
  });

  final String label;
  final AppBadgeTone tone;

  /// 옛 API 호환(작성자 역할 배지 등). null 이면 [tone] 을 그대로 쓴다.
  final bool? tinted;

  AppBadgeTone get _effectiveTone {
    final bool? t = tinted;
    if (t == null) return tone;
    return t ? AppBadgeTone.role : AppBadgeTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final AppBadgeColors colors =
        AppBadgeColors.of(context, _effectiveTone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.badge),
        border: colors.ring ? Border.all(color: AppColors.ring) : null,
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}

/// 톤 → 채움·글자색(단일 소스). 상태칩·도트·카운트 배지가 공유한다.
class AppBadgeColors {
  const AppBadgeColors({
    required this.background,
    required this.foreground,
    this.ring = false,
  });

  final Color background;
  final Color foreground;

  /// 중립 톤은 틴트 대신 유리 안쪽 채움 + 링으로 구분한다.
  final bool ring;

  static AppBadgeColors of(BuildContext context, AppBadgeTone tone) {
    switch (tone) {
      case AppBadgeTone.role:
        final RoleTheme roleTheme = RoleTheme.of(context);
        return AppBadgeColors(
          background: roleTheme.tint,
          foreground: roleTheme.color,
        );
      case AppBadgeTone.neutral:
        return AppBadgeColors(
          background: Colors.white.withValues(alpha: AppGlass.innerFill),
          foreground: AppColors.textSecondary,
          ring: true,
        );
      case AppBadgeTone.info:
        return AppBadgeColors(
          background: RoleColors.student.withValues(alpha: 0.08),
          foreground: RoleColors.student,
        );
      case AppBadgeTone.success:
        return AppBadgeColors(
          background: AppColors.success.withValues(alpha: 0.08),
          foreground: AppColors.success,
        );
      case AppBadgeTone.warning:
        return AppBadgeColors(
          background: AppColors.warning.withValues(alpha: 0.10),
          foreground: AppColors.warning,
        );
      case AppBadgeTone.danger:
        return AppBadgeColors(
          background: AppColors.danger.withValues(alpha: 0.08),
          foreground: AppColors.danger,
        );
    }
  }
}
