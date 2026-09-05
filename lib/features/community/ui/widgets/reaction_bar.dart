import 'package:flutter/material.dart';

import '../../../../design/role_theme.dart' show RoleTheme;
import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_typography.dart';

/// 반응 바 — 좋아요·스크랩·댓글수·신고. 상세 화면 하단/상단에 쓴다.
/// 좋아요/스크랩은 토글(내 반응), 댓글수는 표시, 신고는 시트를 연다.
class ReactionBar extends StatelessWidget {
  const ReactionBar({
    super.key,
    required this.liked,
    required this.scrapped,
    required this.likeCount,
    required this.commentCount,
    required this.onToggleLike,
    required this.onToggleScrap,
    required this.onReport,
  });

  final bool liked;
  final bool scrapped;
  final int likeCount;
  final int commentCount;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleScrap;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _Action(
          icon: liked ? Icons.favorite : Icons.favorite_border,
          label: '좋아요 $likeCount',
          active: liked,
          onTap: onToggleLike,
        ),
        const SizedBox(width: 16),
        _Action(
          icon: Icons.mode_comment_outlined,
          label: '댓글 $commentCount',
          active: false,
          onTap: null,
        ),
        const SizedBox(width: 16),
        _Action(
          icon: scrapped ? Icons.bookmark : Icons.bookmark_border,
          label: '스크랩',
          active: scrapped,
          onTap: onToggleScrap,
        ),
        const Spacer(),
        IconButton(
          tooltip: '신고',
          icon: const Icon(Icons.flag_outlined, color: AppColors.textSecondary),
          onPressed: onReport,
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color =
        active ? RoleTheme.of(context).color : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(label, style: AppTypography.caption.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
