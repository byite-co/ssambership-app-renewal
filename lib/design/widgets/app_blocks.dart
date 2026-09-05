import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'app_empty_state.dart';
import 'app_page.dart';
import 'app_skeleton.dart';
import 'glass_bars.dart';
import 'glass_inner.dart';

/// 화면 조립용 작은 블록들 — A-4a 가 임시 셸 옆에 두었던 것을 디자인 시스템으로 옮겼다.

/// v3 글래스 바텀시트. 역할·테마는 앱 루트가 [MaterialApp] 위에 두르므로 시트
/// 서브트리에 다시 두르지 않는다.
Future<T?> showAppBottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return GlassBottomSheet.show<T>(
    context,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: builder,
  );
}

/// 로딩 자리표시 — 카드 실루엣 N장.
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.cards = 3});

  final int cards;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppPage.contentPadding(context),
      children: <Widget>[
        for (int i = 0; i < cards; i++) ...<Widget>[
          const AppSkeleton(),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// 실패 상태 — 사유 + 다시 시도. 조용히 실패하지 않는다.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = '불러오지 못했어요',
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.cloud_off_rounded,
      title: title,
      description: message,
      actionLabel: '다시 시도',
      onAction: onRetry,
    );
  }
}

/// 필드 라벨 + 입력(또는 임의 child).
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.label,
    required this.child,
    this.help,
    this.error,
  });

  final String label;
  final Widget child;

  /// 입력 아래 안내(범위 등). [error] 가 있으면 그 문장이 대신 나온다.
  final String? help;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final String? note = error ?? help;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        child,
        if (note != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            note,
            style: AppTypography.caption.copyWith(
              color: error != null ? AppColors.danger : AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

enum AppCalloutTone { neutral, warning, danger, success }

/// 안내 블록(내부 글래스). 톤에 따라 아이콘·글자색만 바뀐다.
class AppCallout extends StatelessWidget {
  const AppCallout({
    super.key,
    required this.text,
    this.tone = AppCalloutTone.neutral,
    this.title,
    this.trailing,
  });

  final String text;
  final String? title;
  final AppCalloutTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final Color color;
    final IconData icon;
    switch (tone) {
      case AppCalloutTone.neutral:
        color = AppColors.textSecondary;
        icon = Icons.info_outline_rounded;
      case AppCalloutTone.warning:
        color = AppColors.warning;
        icon = Icons.warning_amber_rounded;
      case AppCalloutTone.danger:
        color = AppColors.danger;
        icon = Icons.error_outline_rounded;
      case AppCalloutTone.success:
        color = roleTheme.color;
        icon = Icons.check_circle_outline_rounded;
    }
    return GlassInner(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null) ...<Widget>[
                  Text(
                    title!,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  text,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 라벨·값 한 줄(표 행). 숫자는 tabular figures 로 우측 정렬.
class AppKeyValueRow extends StatelessWidget {
  const AppKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: (emphasize ? AppTypography.section : AppTypography.body)
                .copyWith(
              color: valueColor ?? AppColors.textPrimary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 탭 가능한 진입 행(아이콘 · 라벨 · 보조 · chevron) — 허브 화면의 목록용.
class AppEntryRow extends StatelessWidget {
  const AppEntryRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 22, color: roleTheme.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label, style: AppTypography.body),
                    if (caption != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        caption!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                trailing!,
              ],
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 섹션 제목(카드 위).
class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(text, style: AppTypography.section)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
