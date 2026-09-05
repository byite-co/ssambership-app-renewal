import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'app_badge.dart';

/// 상태 칩의 의미색(시맨틱 토큰에만 매핑 — hex 하드코딩 금지).
/// 전 tone 이 **역할 무관 공통 시맨틱색**이다.
///
/// [QA-C4] info(진행 중)는 역할 무관 파랑으로 고정한다 — 멘토 화면에서 성공 초록과
/// 반드시 구분돼야 한다. 성공은 v3 성공색(멘토 초록과 같은 값, design-tokens §3-3).
enum StatusTone { neutral, info, success, warning, danger }

/// tone → 시맨틱 색(단일 소스). StatusPill·StatusDot·CountBadge 가 공유한다.
Color statusToneColor(BuildContext context, StatusTone tone) {
  switch (tone) {
    case StatusTone.success:
      return AppColors.success;
    case StatusTone.warning:
      return AppColors.warning;
    case StatusTone.danger:
      return AppColors.danger;
    case StatusTone.info:
      // 역할 무관 고정 파랑 — success(초록)와 반드시 구분돼야 한다(QA-C4).
      return RoleColors.student;
    case StatusTone.neutral:
      return AppColors.textSecondary;
  }
}

AppBadgeTone _badgeTone(StatusTone tone) {
  switch (tone) {
    case StatusTone.success:
      return AppBadgeTone.success;
    case StatusTone.warning:
      return AppBadgeTone.warning;
    case StatusTone.danger:
      return AppBadgeTone.danger;
    case StatusTone.info:
      return AppBadgeTone.info;
    case StatusTone.neutral:
      return AppBadgeTone.neutral;
  }
}

/// 상태 색 도트(D1-B). 상태칩 앞에서 스캔성을 높이는 작은 solid 원.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, this.tone = StatusTone.neutral, this.size = 8});

  final StatusTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: statusToneColor(context, tone),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// 상태 한글 칩 — v3 상태 배지(모서리 6 · 옅은 틴트 · 13 SemiBold).
/// label 은 '한글'만 받는다(영문 enum/코드 노출 금지). 색은 tone → 시맨틱 토큰.
/// [showDot] = true 면 라벨 앞에 같은 색 solid 도트(스캔성↑, D1-B).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.showDot = false,
  });

  final String label;
  final StatusTone tone;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final AppBadgeColors colors = AppBadgeColors.of(context, _badgeTone(tone));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.badge),
        border: colors.ring ? Border.all(color: AppColors.ring) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showDot) ...<Widget>[
            StatusDot(tone: tone, size: 6),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
