import 'package:flutter/material.dart';

import '../../../../design/shape_tokens.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../../../design/widgets/app_card.dart';
import '../../../../design/widgets/initial_avatar.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/community_labels.dart';
import '../../data/community_models.dart';
import '../../data/community_post_image_url_resolver.dart';

/// 게시판 글 카드(리스트 한 행). 첫 이미지 미리보기·카테고리칩·제목·작성자·
/// 시간·댓글수·좋아요.
///
/// 미리보기는 웹 목록 카드(CommunityPostCard — `imageUrls[0]`, 고정 높이,
/// object-cover)와 동일 계약: **첫 번째 image ref 만** 서명 URL 로 해석해
/// 표시하고, 나머지 ref 는 목록에서 렌더하지 않는다(전체 표시는 상세 화면).
/// 이미지가 없으면 기존 텍스트 카드와 완전히 동일하다. 서명·로드 실패는
/// 미리보기 영역의 중립 플레이스홀더로 끝나고 제목·본문·통계·탭 동작에
/// 전파되지 않는다.
///
/// ★ 내부 id·원문 ref·UID·Storage 경로·서명 URL 은 문구·semantic label 어디
///   에도 노출하지 않는다.
class BoardPostCard extends StatefulWidget {
  BoardPostCard({
    super.key,
    required this.post,
    required this.onOpen,
    CommunityPostImageUrlResolver? imageUrlResolver,
  }) : imageUrlResolver =
            imageUrlResolver ?? sharedCommunityPostImageUrlResolver;

  final BoardPost post;
  final VoidCallback onOpen;

  /// 서명 URL 리졸버 — 기본은 앱 공유 인스턴스(TTL 캐시·single-flight 공유,
  /// 카드마다 새로 만들지 않는다). 테스트 주입 seam.
  final CommunityPostImageUrlResolver imageUrlResolver;

  @override
  State<BoardPostCard> createState() => _BoardPostCardState();
}

class _BoardPostCardState extends State<BoardPostCard> {
  /// 진행 중/완료된 첫 이미지 해석. null = 이미지 없는 카드(미리보기 영역 없음).
  Future<Uri?>? _thumb;

  /// [_thumb] 를 시작시킨 ref — 일반 rebuild 에서 재해석하지 않기 위한 기준.
  String? _thumbRef;

  String? get _firstRef =>
      widget.post.imageRefs.isEmpty ? null : widget.post.imageRefs.first;

  @override
  void initState() {
    super.initState();
    _startResolve();
  }

  @override
  void didUpdateWidget(BoardPostCard old) {
    super.didUpdateWidget(old);
    // 일반 rebuild 에서는 기존 Future 를 유지한다(재서명 요청 0).
    // post 교체·첫 ref 변경·리졸버 교체 시에만 새로 해석한다.
    if (old.post.id != widget.post.id ||
        !identical(old.imageUrlResolver, widget.imageUrlResolver) ||
        _thumbRef != _firstRef) {
      _startResolve();
    }
  }

  void _startResolve() {
    final String? ref = _firstRef;
    _thumbRef = ref;
    _thumb = ref == null ? null : widget.imageUrlResolver.resolve(ref);
  }

  /// 미리보기 실패·로딩용 중립 영역 — 문구·원문 정보 없이 아이콘만.
  Widget _neutralBox() {
    return const ColoredBox(
      color: ColorTokens.elevated,
      child: Center(
        child: Icon(Icons.image_outlined, size: 28, color: ColorTokens.muted),
      ),
    );
  }

  /// 첫 이미지 미리보기(웹 h-40 · object-cover 와 동일한 고정 높이·cover).
  Widget _preview(Future<Uri?> thumb) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: AppShape.inputRadius,
        child: SizedBox(
          key: const ValueKey<String>('board-card-thumb'),
          height: 160,
          width: double.infinity,
          child: FutureBuilder<Uri?>(
            future: thumb,
            builder: (BuildContext context, AsyncSnapshot<Uri?> snap) {
              if (snap.connectionState != ConnectionState.done) {
                return _neutralBox();
              }
              final Uri? uri = snap.data;
              if (uri == null) return _neutralBox(); // 서명 실패 — 카드 유지
              return Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                // 로드 실패도 이 영역 안에서 끝난다(카드 전체 미전파).
                errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                    _neutralBox(),
                loadingBuilder: (BuildContext c, Widget child,
                    ImageChunkEvent? progress) {
                  if (progress == null) return child;
                  return _neutralBox();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final BoardPost post = widget.post;
    final Future<Uri?>? thumb = _thumb;
    return AppCard(
      onTap: widget.onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 이미지 없는 글은 미리보기 영역 자체가 없다(기존 카드와 동일).
          if (thumb != null) _preview(thumb),
          Row(
            children: <Widget>[
              AppBadge(label: communityCategoryLabel(post.category), tinted: true),
              const Spacer(),
              Text(Formatters.relativeKorean(post.createdAt),
                  style: AppType.caption),
            ],
          ),
          const SizedBox(height: 8),
          Text(post.title,
              style: AppType.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              InitialAvatar(name: post.authorName, size: 22, tinted: false),
              const SizedBox(width: 6),
              Text(post.authorName, style: AppType.caption),
              const Spacer(),
              _Metric(icon: Icons.favorite_border, value: post.likeCount),
              const SizedBox(width: 12),
              _Metric(icon: Icons.mode_comment_outlined, value: post.commentCount),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value});
  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: ColorTokens.muted),
        const SizedBox(width: 3),
        Text('$value', style: AppType.caption),
      ],
    );
  }
}
