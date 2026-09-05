import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';
import 'status_pill.dart';

/// 카운트 배지(D1-D) — 주목 필요한 개수를 채운 배지로. ★값(count)만 받는 순수 위젯★.
///
/// 색: tone 을 주면 그 상태색, 안 주면 **역할색**(학생 파랑/멘토 초록 — design-v3 §3-1
/// '답변 1'). solid 배경 + 흰 숫자(tabular). count ≤ 0 이면 아무것도 그리지 않는다.
/// [max] 초과는 'max+'(예: 99+).
class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.count,
    this.tone,
    this.max = 99,
  });

  final int count;

  /// null 이면 역할색을 쓴다(정체성 유지). 상태를 뜻할 때만 tone 을 준다.
  final StatusTone? tone;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final StatusTone? t = tone;
    final Color c =
        t == null ? RoleTheme.of(context).color : statusToneColor(context, t);
    final String text = count > max ? '$max+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        text,
        style: AppTypography.meta.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          height: 1.2,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
