import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/auth/auth_service.dart' as auth;
import '../../design/app_theme.dart' as v3;
import '../../design/role_theme.dart';
import '../../design/tokens/app_colors.dart';
import '../../design/tokens/app_spacing.dart';
import '../../design/tokens/app_typography.dart';
import '../../design/widgets/app_background.dart';
import '../../design/widgets/app_empty_state.dart';
import '../../design/widgets/app_skeleton.dart';
import '../../design/widgets/glass_bars.dart';
import '../../design/widgets/glass_inner.dart';

/// A-4a 새 화면의 공통 껍데기 — A-6a 컴포넌트만으로 합성한다.
///
/// 앱 트리는 아직 v3 테마에 연결돼 있지 않다(A-6b). 그래서 각 새 화면이 이 위젯으로
/// v3 [AppTheme]·[RoleTheme]·[AppBackground]·[GlassAppBar] 를 스스로 두른다.
/// 역할색은 [AppScope] 의 현재 역할에서 정한다(멘토 초록·그 외 학생 파랑).
class V3Page extends StatelessWidget {
  const V3Page({
    super.key,
    required this.title,
    required this.body,
    this.actions = const <Widget>[],
    this.showBack = true,
    this.roleOverride,
    this.bottom,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;

  /// 뒤로 가기 표시. pushed 화면은 true, 탭 본문에 임베드하면 false.
  final bool showBack;

  /// 테스트·갤러리용 역할 강제. null 이면 AppScope 의 현재 역할.
  final AppRole? roleOverride;

  /// 하단 고정 영역(저장 버튼 등). 글래스 바로 감싼다.
  final Widget? bottom;

  /// [extendBodyBehindAppBar] 위에서 스크롤 본문이 써야 할 상단 여백.
  static double topInset(BuildContext context) =>
      MediaQuery.paddingOf(context).top + kToolbarHeight;

  /// 스크롤 본문 기본 패딩(좌우 20 · 앱바 아래 12 · 하단 24).
  static EdgeInsets contentPadding(BuildContext context, {double bottom = 24}) =>
      EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        topInset(context) + 12,
        AppSpacing.screenH,
        bottom,
      );

  static AppRole roleOf(BuildContext context) {
    final AppDependencies? deps = AppScope.maybeOf(context);
    return deps?.auth.currentRole == auth.AppRole.mentor
        ? AppRole.mentor
        : AppRole.student;
  }

  @override
  Widget build(BuildContext context) {
    final AppRole role = roleOverride ?? roleOf(context);
    return Theme(
      data: v3.AppTheme.build(),
      child: RoleTheme(
        role: role,
        child: AppBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            extendBody: bottom != null,
            appBar: GlassAppBar(
              title: Text(title),
              leading: showBack
                  ? IconButton(
                      tooltip: '뒤로',
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
              actions: actions,
            ),
            body: body,
            bottomNavigationBar: bottom == null
                ? null
                : GlassBottomSheet(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: bottom!,
                  ),
          ),
        ),
      ),
    );
  }
}

/// v3 글래스 바텀시트 — 호출 화면의 역할·테마를 시트 서브트리에 다시 두른다
/// (모달 시트는 Navigator 아래에 붙어 [V3Page] 의 [RoleTheme] 을 상속하지 못한다).
Future<T?> showV3BottomSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  final AppRole role = RoleTheme.of(context).role;
  return GlassBottomSheet.show<T>(
    context,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: (BuildContext sheetContext) => Theme(
      data: v3.AppTheme.build(),
      child: RoleTheme(role: role, child: builder(sheetContext)),
    ),
  );
}

/// 로딩 자리표시 — 카드 실루엣 3장.
class V3LoadingView extends StatelessWidget {
  const V3LoadingView({super.key, this.cards = 3});

  final int cards;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: V3Page.contentPadding(context),
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
class V3ErrorView extends StatelessWidget {
  const V3ErrorView({
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
    return Padding(
      padding: EdgeInsets.only(top: V3Page.topInset(context)),
      child: AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: title,
        description: message,
        actionLabel: '다시 시도',
        onAction: onRetry,
      ),
    );
  }
}

/// 필드 라벨 + 입력(또는 임의 child).
class V3Field extends StatelessWidget {
  const V3Field({
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

enum V3CalloutTone { neutral, warning, danger, success }

/// 안내 블록(내부 글래스). 톤에 따라 아이콘·글자색만 바뀐다.
class V3Callout extends StatelessWidget {
  const V3Callout({
    super.key,
    required this.text,
    this.tone = V3CalloutTone.neutral,
    this.title,
    this.trailing,
  });

  final String text;
  final String? title;
  final V3CalloutTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final Color color;
    final IconData icon;
    switch (tone) {
      case V3CalloutTone.neutral:
        color = AppColors.textSecondary;
        icon = Icons.info_outline_rounded;
      case V3CalloutTone.warning:
        color = AppColors.warning;
        icon = Icons.warning_amber_rounded;
      case V3CalloutTone.danger:
        color = AppColors.danger;
        icon = Icons.error_outline_rounded;
      case V3CalloutTone.success:
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
class V3KeyValueRow extends StatelessWidget {
  const V3KeyValueRow({
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
class V3EntryRow extends StatelessWidget {
  const V3EntryRow({
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
class V3SectionTitle extends StatelessWidget {
  const V3SectionTitle(this.text, {super.key, this.trailing});

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
