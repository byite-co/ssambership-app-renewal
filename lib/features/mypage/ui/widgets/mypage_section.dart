import 'package:flutter/material.dart';

import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_spacing.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/glass_card.dart';

/// 마이페이지 섹션 컨테이너(제목 + 유리 카드 본문). 세로로 잘게 쪼개지 않게 카드형으로 묶는다.
/// 모든 섹션이 같은 헤더/여백을 쓰도록 공통화(중복 제거).
class MyPageSection extends StatelessWidget {
  const MyPageSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.icon,
  });

  final String title;
  final Widget child;

  /// 제목 우측 보조(예: '조회만' 배지).
  final Widget? trailing;

  /// 제목 앞 leading 아이콘(선택). 없으면 제목만. 색은 보조색.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                ],
                Text(title, style: AppTypography.section),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
          GlassCard(child: child),
        ],
      ),
    );
  }
}

/// 섹션 안의 '한 줄 진입' 행(아이콘 + 라벨 + 우측 chevron/보조). 탭 가능.
class MyPageRow extends StatelessWidget {
  const MyPageRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailingText,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? trailingText;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: Padding(
        // 8: 설정 섹션 전체(토글 6 + 행 5 + 버튼)가 800×600 테스트 표면에 들어가야 한다.
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTypography.body)),
            if (trailingText != null)
              Text(trailingText!, style: AppTypography.captionSecondary),
            if (showChevron && onTap != null) ...<Widget>[
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
