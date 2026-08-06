import 'package:flutter/material.dart';

import '../../../../design/role_accent.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/shape_tokens.dart';
import '../../../../design/spacing_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../../../design/widgets/initial_avatar.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/community_labels.dart';
import '../../data/community_models.dart';
import '../../data/community_post_image_url_resolver.dart';
import '../../data/community_read_repository.dart';
import '../../data/community_write_repository.dart';
import '../widgets/block_author_action.dart';
import '../widgets/comment_tile.dart';
import '../widgets/content_policy_gate.dart';
import '../widgets/reaction_bar.dart';
import '../widgets/report_sheet.dart';
import 'board_write_screen.dart';
import '../../../../shared/errors/friendly_error.dart';

/// 게시판 상세 — 본문 + 이미지 + 반응(좋아요·스크랩·신고) + 댓글(읽기+작성).
/// ★ 글 작성·수정은 학생·멘토 모두 앱에서 가능하다(Build 13) — 직접 table
///   write 가 아니라 `api_app_v1` RPC(community_post_create/update) 단일
///   경로다. 수정 진입점은 이 화면의 내 글 전용 메뉴([_editMyPost]).
class BoardDetailScreen extends StatefulWidget {
  BoardDetailScreen({
    super.key,
    required this.post,
    required this.read,
    required this.write,
    CommunityPostImageUrlResolver? imageUrlResolver,
  }) : imageUrlResolver =
            imageUrlResolver ?? sharedCommunityPostImageUrlResolver;

  final BoardPost post;
  final CommunityReadRepository read;
  final CommunityWriteRepository write;

  /// 첨부 이미지 서명 URL 리졸버(테스트 주입 seam — 기본은 앱 공유 인스턴스).
  final CommunityPostImageUrlResolver imageUrlResolver;

  @override
  State<BoardDetailScreen> createState() => _BoardDetailScreenState();
}

class _BoardDetailScreenState extends State<BoardDetailScreen> {
  final TextEditingController _input = TextEditingController();
  late Future<List<CommunityComment>> _comments;

  bool _liked = false;
  bool _scrapped = false;
  late int _likeCount;
  bool _busy = false;

  /// §4: 이 상세에서 서버 상태가 바뀌었는지(댓글·반응·차단). pop(true) 로
  /// 목록에 알리고, 목록은 그때만 첫 페이지를 재조회한다.
  bool _changed = false;

  /// §4: 댓글 수 최신값(목록 스냅샷 p.commentCount 의 상세 내 stale 해소).
  int? _commentCountOverride;

  /// N40: 본인 진입 조회수 증분(서버 성공 시 1) — 표시에만 가산.
  int _viewCountBump = 0;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _comments = widget.read.comments(CommunityPostType.board, widget.post.id);
    _loadReactionState();
    // 상세 진입 시 조회수 +1(진입당 1회). RPC 부재 시 조용히 무시.
    // N40: 서버 증분 성공 시 본인 진입 +1 을 표시에 반영(목록 스냅샷 고정 해소).
    widget.write.incrementBoardView(widget.post.id).then((bool ok) {
      if (ok && mounted) setState(() => _viewCountBump = 1);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadReactionState() async {
    try {
      // C9: 이 글 1건으로 서버 필터 + 좋아요·스크랩 병렬 조회.
      final List<Set<String>> rs = await Future.wait(<Future<Set<String>>>[
        widget.read.myBoardReactionIds(CommunityWriteRepository.reactionLike,
            postId: widget.post.id),
        widget.read.myBoardReactionIds(CommunityWriteRepository.reactionScrap,
            postId: widget.post.id),
      ]);
      if (!mounted) return;
      setState(() {
        _liked = rs[0].contains(widget.post.id);
        _scrapped = rs[1].contains(widget.post.id);
      });
    } catch (_) {
      // 반응 상태 조회 실패는 화면을 막지 않는다(기본 미반응).
    }
  }

  Future<void> _toggleLike() async {
    final bool next = !_liked;
    setState(() {
      _liked = next;
      _likeCount += next ? 1 : -1;
    });
    try {
      await widget.write.toggleBoardReaction(
        postId: widget.post.id,
        type: CommunityWriteRepository.reactionLike,
        on: next,
      );
      _changed = true; // like_count 서버 변경 — 목록 카드 갱신 필요.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = !next;
        _likeCount += next ? -1 : 1;
      });
      _snack('반응 처리에 실패했어요. ${friendlyError(e)}');
    }
  }

  Future<void> _toggleScrap() async {
    final bool next = !_scrapped;
    setState(() => _scrapped = next);
    try {
      await widget.write.toggleBoardReaction(
        postId: widget.post.id,
        type: CommunityWriteRepository.reactionScrap,
        on: next,
      );
      _changed = true;
      _snack(next ? '스크랩했어요.' : '스크랩을 해제했어요.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _scrapped = !next);
      _snack('처리에 실패했어요. ${friendlyError(e)}');
    }
  }

  Future<void> _report() async {
    final String? reason = await showReportSheet(context);
    if (reason == null) return;
    try {
      await widget.write.report(
        targetType: 'community_post',
        targetId: widget.post.id,
        reason: reason,
      );
      _snack('신고가 접수되었어요. 운영팀이 검토할게요.');
    } catch (e) {
      _snack('신고 접수에 실패했어요. ${friendlyError(e)}');
    }
  }

  /// 내 글 여부 — 수정 진입점 노출 게이트(내부 비교 전용, UUID 비노출).
  /// ★ 역할(학생/멘토) 무관 — 자기 글이면 동일하게 노출. 편의 게이트일 뿐
  ///   보안 정본은 서버(community_post_update 의 author_id 검사)다.
  bool get _isMyPost {
    final String? uid = widget.write.currentUserId;
    final String? authorId = widget.post.authorId;
    return uid != null && authorId != null && uid == authorId;
  }

  /// 내 글 수정 — 수정 화면으로. 성공(pop true)하면 상세를 닫아 목록을
  /// 새로고침시킨다(상세의 글 스냅샷은 이미 낡은 값이라 유지하지 않는다).
  Future<void> _editMyPost() async {
    final bool? updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BoardWriteScreen(
          write: widget.write,
          editing: widget.post,
        ),
      ),
    );
    if (updated == true && mounted) Navigator.of(context).pop(true);
  }

  /// 내 글 삭제 — 서버 소프트삭제 RPC 단일 경로(N3). 성공 시 상세를 닫아
  /// 목록을 새로고침시킨다(deleted_at 이 찍힌 행은 뷰에서 사라진다).
  Future<void> _deleteMyPost() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('글을 삭제할까요?'),
        content: const Text('삭제한 글은 다시 볼 수 없어요.'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.write.deleteMyPost(widget.post.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('글 삭제에 실패했어요. ${friendlyError(e)}');
    }
  }

  /// 글 작성자 차단 → 성공 시 상세를 닫아 목록으로(목록은 재조회 시 숨겨짐).
  /// C10: author_id 는 이미 뷰(community_posts_v1) 행에 있으므로 재조회 없이
  /// 그대로 쓴다 — community_posts 베이스 테이블 접근 0건 계약.
  Future<void> _blockPostAuthor() async {
    final String? authorId = widget.post.authorId;
    if (authorId == null) {
      // 뷰 행에 작성자 id 가 없으면 차단 불가(베이스 재조회로 우회하지 않는다).
      _snack('차단에 실패했어요. 잠시 후 다시 시도해 주세요.');
      return;
    }
    final bool blocked = await confirmAndBlockAuthor(context, authorId: authorId);
    if (blocked && mounted) Navigator.of(context).pop(true);
  }

  /// 댓글 신고 → content_reports(target_type='board_comment' — 정본 comments
  /// 행. 서버 allowlist 정본: 구 'comment' 는 거부돼 접수가 실패했다 — live
  /// bug 수정).
  Future<void> _reportComment(String commentId) async {
    final String? reason = await showReportSheet(context);
    if (reason == null) return;
    try {
      await widget.write.report(
        targetType: 'board_comment',
        targetId: commentId,
        reason: reason,
      );
      _snack('신고가 접수되었어요. 운영팀이 검토할게요.');
    } catch (e) {
      _snack('신고 접수에 실패했어요. ${friendlyError(e)}');
    }
  }

  /// 댓글 작성자 차단 → 성공 시 댓글 목록 재조회(차단 작성자 댓글 숨김).
  /// 게시판 댓글은 정본 comments 행에서 author_id 를 찾는다(v16 정본 전환).
  Future<void> _blockCommentAuthor(String commentId) async {
    final bool blocked = await confirmAndBlockAuthor(
      context,
      table: 'comments',
      contentId: commentId,
    );
    if (blocked && mounted) {
      _changed = true;
      _reloadComments();
    }
  }

  /// 댓글 재조회 + 댓글 수 동기화. Future 교체 방식이라 FutureBuilder 가
  /// 최신 future 만 반영(늦은 응답이 덮지 않음), 콜백은 mounted 가드.
  void _reloadComments() {
    final Future<List<CommunityComment>> next =
        widget.read.comments(CommunityPostType.board, widget.post.id);
    // ★ 블록 바디: 화살표로 Future 를 대입하면 'setState callback returned a
    //   Future' 로 리빌드가 취소된다(§4 공통 함정).
    setState(() {
      _comments = next;
    });
    next.then((List<CommunityComment> list) {
      if (!mounted) return;
      setState(() => _commentCountOverride = list.length);
    }).catchError((Object _) {
      // 재조회 실패 시 기존 표시값 유지(정상 데이터를 지우지 않는다).
    });
  }

  Future<void> _send() async {
    final String body = _input.text.trim();
    if (body.isEmpty || _busy) return;
    // 게시 전 커뮤니티 이용 규정 동의(UGC 심사 요건). 미동의 시 등록 중단.
    if (!await ContentPolicyGate.ensureAgreed(context)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await widget.write.addComment(
        postType: CommunityPostType.board,
        postId: widget.post.id,
        body: body,
      );
      if (!mounted) return; // ★ await 중 화면이 닫혔으면 상태 갱신 금지
      _input.clear();
      _changed = true;
      _reloadComments();
    } catch (e) {
      _snack('댓글 등록에 실패했어요. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final BoardPost p = widget.post;
    // §4: 뒤로가기에도 변경 여부(_changed)를 목록에 전달(iq_detail 과 동일 패턴).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: _buildScaffold(p),
    );
  }

  Widget _buildScaffold(BoardPost p) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: '더보기',
            onSelected: (String v) {
              if (v == 'edit') _editMyPost();
              if (v == 'delete') _deleteMyPost();
              if (v == 'block') _blockPostAuthor();
            },
            itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
              // 수정·삭제는 내 글에만 노출(타인 글 UI 미노출 — 서버도 거부).
              if (_isMyPost)
                const PopupMenuItem<String>(value: 'edit', child: Text('수정')),
              if (_isMyPost)
                const PopupMenuItem<String>(value: 'delete', child: Text('삭제')),
              const PopupMenuItem<String>(
                  value: 'block', child: Text('이 사용자 차단')),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH, 16, AppSpacing.screenH, 16),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AppBadge(
                        label: communityCategoryLabel(p.category),
                        tinted: true),
                    const Spacer(),
                    Text(Formatters.relativeKorean(p.createdAt),
                        style: AppType.caption),
                  ],
                ),
                const SizedBox(height: AppSpacing.titleBody),
                Text(p.title, style: AppType.title),
                const SizedBox(height: AppSpacing.titleBody),
                Row(
                  children: <Widget>[
                    InitialAvatar(name: p.authorName, size: 28, tinted: false),
                    const SizedBox(width: 8),
                    Text(p.authorName, style: AppType.caption),
                    const SizedBox(width: 10),
                    Text('조회 ${p.viewCount + _viewCountBump}', style: AppType.caption),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),
                Text(
                  p.body?.trim().isNotEmpty == true
                      ? p.body!.trim()
                      : '(내용 없음)',
                  style: AppType.body,
                ),
                // 첨부 이미지 — imageRefs 순서대로. 한 장의 실패가 본문·다른
                // 이미지 표시를 막지 않는다(장별 독립 해석·플레이스홀더).
                for (final String ref in p.imageRefs) ...<Widget>[
                  const SizedBox(height: AppSpacing.s16),
                  _PostImage(
                    key: ValueKey<String>('post-image-$ref'),
                    imageRef: ref,
                    resolver: widget.imageUrlResolver,
                  ),
                ],
                const SizedBox(height: AppSpacing.s24),
                ReactionBar(
                  liked: _liked,
                  scrapped: _scrapped,
                  likeCount: _likeCount,
                  commentCount: _commentCountOverride ?? p.commentCount,
                  onToggleLike: _toggleLike,
                  onToggleScrap: _toggleScrap,
                  onReport: _report,
                ),
                const Divider(height: 28, color: ColorTokens.border),
                _commentList(),
              ],
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _commentList() {
    return FutureBuilder<List<CommunityComment>>(
      future: _comments,
      builder:
          (BuildContext context, AsyncSnapshot<List<CommunityComment>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Text('댓글을 불러오지 못했어요.', style: AppType.caption);
        }
        final List<CommunityComment> comments =
            snap.data ?? <CommunityComment>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 헤더: "댓글 {개수}"(동적 — 현재 리스트 length). 스타일 title.
            Text('댓글 ${comments.length}', style: AppType.title),
            const SizedBox(height: AppSpacing.titleBody),
            if (comments.isEmpty)
              Text('첫 댓글을 남겨보세요.', style: AppType.caption)
            else
              // 댓글 항목 '사이에만' 옅은 구분선(첫 위·마지막 아래 없음).
              for (int i = 0; i < comments.length; i++) ...<Widget>[
                if (i > 0)
                  const Divider(
                      height: 1, thickness: 0.5, color: ColorTokens.border),
                CommentTile(
                  comment: comments[i],
                  onReport: () => _reportComment(comments[i].id),
                  onBlock: () => _blockCommentAuthor(comments[i].id),
                ),
              ],
          ],
        );
      },
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: const BoxDecoration(
          color: ColorTokens.surface,
          border: Border(top: BorderSide(color: ColorTokens.border)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _input,
                style: AppType.body,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: '댓글 입력',
                  filled: true,
                  fillColor: ColorTokens.elevated,
                  border: OutlineInputBorder(
                    borderRadius: AppShape.inputRadius,
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.send_rounded,
                  color:
                      _busy ? ColorTokens.muted : AppAccent.of(context).accent),
              onPressed: _busy ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// 게시글 첨부 이미지 1장 — 서명 URL 해석 후 표시.
///
/// 실패(해석 실패·로드 실패)는 이 위젯 안의 중립 플레이스홀더로 끝난다 —
/// 본문·다른 이미지·댓글 표시에 전파되지 않는다. ★ 원문 ref·UID·Storage
/// 경로·서명 URL 은 어떤 상태에서도 화면에 싣지 않는다.
class _PostImage extends StatefulWidget {
  const _PostImage({
    super.key,
    required this.imageRef,
    required this.resolver,
  });

  final String imageRef;
  final CommunityPostImageUrlResolver resolver;

  @override
  State<_PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<_PostImage> {
  late Future<Uri?> _uri;

  @override
  void initState() {
    super.initState();
    // 리졸버가 TTL 캐시를 갖는다 — 재진입 시 만료 전 URL 만 재사용되고,
    // 만료 후엔 이 호출이 새로 발급한다.
    _uri = widget.resolver.resolve(widget.imageRef);
  }

  @override
  void didUpdateWidget(_PostImage old) {
    super.didUpdateWidget(old);
    if (old.imageRef != widget.imageRef) {
      _uri = widget.resolver.resolve(widget.imageRef);
    }
  }

  Widget _placeholder({required Widget child}) {
    return Container(
      height: 160,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: ColorTokens.elevated,
        borderRadius: AppShape.inputRadius,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uri?>(
      future: _uri,
      builder: (BuildContext context, AsyncSnapshot<Uri?> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _placeholder(
              child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }
        final Uri? uri = snap.data;
        if (uri == null) {
          // 해석 실패 — 원문 ref·경로 없이 중립 안내만.
          return _placeholder(
            child: const Text('이미지를 불러오지 못했어요.', style: AppType.caption),
          );
        }
        return ClipRRect(
          borderRadius: AppShape.inputRadius,
          child: Image.network(
            uri.toString(),
            fit: BoxFit.fitWidth,
            width: double.infinity,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                _placeholder(
              child: const Text('이미지를 불러오지 못했어요.', style: AppType.caption),
            ),
            loadingBuilder: (BuildContext c, Widget child,
                ImageChunkEvent? progress) {
              if (progress == null) return child;
              return _placeholder(
                  child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ));
            },
          ),
        );
      },
    );
  }
}
