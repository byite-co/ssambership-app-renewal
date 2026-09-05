import 'package:flutter/material.dart';

import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/initial_avatar.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/community_models.dart';

/// 댓글 한 줄. 이니셜아바타 + 작성자명 + 시간 + 본문. 내부 id 비노출.
/// [onReport] 지정 시 ⋯ 메뉴에 '신고', [onBlock] 지정 시 '이 사용자 차단',
/// [onDelete] 지정 시 '삭제'(내 댓글 전용 — 노출 게이트는 호출부 책임) 노출.
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.onReport,
    this.onBlock,
    this.onDelete,
  });

  final CommunityComment comment;
  final VoidCallback? onReport;
  final VoidCallback? onBlock;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InitialAvatar(name: comment.authorName, size: 30, tinted: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(comment.authorName,
                        style: AppTypography.caption
                            .copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text(Formatters.relativeKorean(comment.createdAt),
                        style: AppTypography.meta),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.body, style: AppTypography.body),
              ],
            ),
          ),
          if (onReport != null || onBlock != null || onDelete != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded,
                  size: 18, color: AppColors.textSecondary),
              tooltip: '더보기',
              onSelected: (String v) {
                if (v == 'report') onReport?.call();
                if (v == 'block') onBlock?.call();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                if (onDelete != null)
                  const PopupMenuItem<String>(
                      value: 'delete', child: Text('삭제')),
                if (onReport != null)
                  const PopupMenuItem<String>(
                      value: 'report', child: Text('신고')),
                if (onBlock != null)
                  const PopupMenuItem<String>(
                      value: 'block', child: Text('이 사용자 차단')),
              ],
            ),
        ],
      ),
    );
  }
}
