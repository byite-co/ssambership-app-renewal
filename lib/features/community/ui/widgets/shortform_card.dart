import 'package:flutter/material.dart';

import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_glass.dart';
import '../../../../design/tokens/app_spacing.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../data/community_models.dart';
import 'thumbnail_view.dart';

/// 숏폼 카드(세로 피드 한 칸) — design-v3 §5-6: 정보는 **미디어 위 오버레이**.
/// 어두운 미디어 위 아래쪽 스크림에 제목·멘토 배지·작성자·좋아요·조회수를 얹는다.
///
/// 실제 재생은 상세(video_player)가 담당하고 피드 인라인 재생은 하지 않는다 —
/// 카드 전체 탭 = 상세 진입이므로 중앙 재생 아이콘은 '영상 열기' 어포던스다
/// (거짓 CTA 아님). 웹이 thumbnail_url 을 null 로 저장하는 현재 계약에서는
/// 거짓 썸네일 대신 중립 영상 플레이스홀더 + 재생 어포던스를 그린다(App-SF1).
class ShortformCard extends StatelessWidget {
  const ShortformCard({super.key, required this.post, required this.onOpen});

  final ShortformPost post;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final TextStyle onMedia = AppTypography.captionSecondary.copyWith(
      color: Colors.white.withValues(alpha: 0.85),
    );
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: const <BoxShadow>[AppGlass.panelShadow],
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ThumbnailView(url: post.thumbnailUrl, showPlayAffordance: true),
              // 아래쪽 스크림 — 미디어 위 글자 대비(히트테스트 제외).
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const <double>[0.45, 1],
                        colors: <Color>[
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          if (post.authorRole == 'mentor') ...<Widget>[
                            const _OnMediaBadge(label: '멘토'),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              post.authorName,
                              style: onMedia,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        post.title,
                        style: AppTypography.bodyStrong.copyWith(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          const Icon(Icons.favorite_border,
                              size: 15, color: Colors.white70),
                          const SizedBox(width: 3),
                          Text('${post.likeCount}', style: onMedia),
                          const SizedBox(width: 12),
                          const Icon(Icons.visibility_outlined,
                              size: 15, color: Colors.white70),
                          const SizedBox(width: 3),
                          Text('${post.viewCount}', style: onMedia),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 미디어 위 작은 배지 — 흰색 반투명 채움 + 흰 글자.
class _OnMediaBadge extends StatelessWidget {
  const _OnMediaBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        label,
        style: AppTypography.meta.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
