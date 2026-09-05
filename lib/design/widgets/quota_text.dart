import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_typography.dart';

/// 남은 질문 표기. ★ 반드시 "잔여 N개" 형식 — '0/4' 같은 분수 표기 금지.
class QuotaText extends StatelessWidget {
  const QuotaText({
    super.key,
    required this.remaining,
    this.emphasize = true,
  });

  /// 남은 개수(미확정/없음이면 호출부에서 이 위젯을 쓰지 않는다).
  final int remaining;

  /// true 면 역할색 강조.
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Text(
      '잔여 $remaining개',
      style: AppTypography.bodyStrong.copyWith(
        color: emphasize ? RoleTheme.of(context).color : AppColors.textPrimary,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}
