import 'package:flutter/material.dart';

import '../../../../design/role_accent.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/shape_tokens.dart';
import '../../../../design/spacing_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/app_badge.dart';
import '../../data/community_models.dart';
import '../../data/community_read_repository.dart';
import '../../data/community_write_repository.dart';
import '../../data/shortform_media_url_resolver.dart';
import '../widgets/block_author_action.dart';
import '../widgets/comment_tile.dart';
import '../widgets/content_policy_gate.dart';
import '../widgets/reaction_bar.dart';
import '../widgets/report_sheet.dart';
import '../widgets/thumbnail_view.dart';
import 'shortform_video_port.dart';
import '../../../../shared/errors/friendly_error.dart';

/// 숏폼 상세 — 세로 영상 재생(video_player, 탭=재생/일시정지) + 반응 + 댓글.
///
/// videoUrl 정본은 Storage 참조(`shortform-videos/{userId}/{uuid}.{ext}`)라
/// [ShortformMediaUrlResolver] 로 짧은 TTL 서명 URL 을 해석한 뒤 재생한다
/// (legacy http(s) 절대 URL 은 해석 없이 그대로 재생 — 기존 계약 유지).
/// 해석·초기화 실패는 크래시 없이 명시적 폴백 + 수동 재시도로 수렴한다.
/// 작성은 '댓글'만.
class ShortformDetailScreen extends StatefulWidget {
  const ShortformDetailScreen({
    super.key,
    required this.post,
    required this.read,
    required this.write,
    this.videoControllerFactory = createShortformVideoController,
    this.mediaResolver,
  });

  final ShortformPost post;
  final CommunityReadRepository read;
  final CommunityWriteRepository write;

  /// 재생 컨트롤러 팩토리 — 테스트에서 fake 주입(실네트워크 재생 회피).
  final ShortformVideoControllerFactory videoControllerFactory;

  /// 저장값 → 재생 URL 리졸버. null 이면 앱 전역 공유 Supabase 구현
  /// ([sharedShortformMediaUrlResolver])을 쓴다. 테스트에서 fake 백엔드를
  /// 물린 리졸버를 주입해 실네트워크·실 Storage 없이 전 상태를 재현한다.
  final ShortformMediaUrlResolver? mediaResolver;

  @override
  State<ShortformDetailScreen> createState() => ShortformDetailScreenState();
}

/// 미디어 로드 단계(§5-2). resolving(참조 해석) → initializing(플레이어
/// 초기화) → ready, 또는 noMedia/failed/invalidReference 로 수렴한다.
enum _ShortformMediaPhase {
  resolving,
  noMedia,
  initializing,
  ready,
  failed,
  invalidReference,
}

/// 상태를 공개해 테스트가 [retryMedia] 로 로드 세대(viewLoadGeneration) 폐기
/// 계약을 검증할 수 있게 한다(ShortformFeedViewState 공개와 같은 규약).
class ShortformDetailScreenState extends State<ShortformDetailScreen> {
  final TextEditingController _input = TextEditingController();
  late Future<List<CommunityComment>> _comments;

  bool _liked = false;
  bool _scrapped = false;
  late int _likeCount;
  bool _busy = false;

  ShortformVideoController? _video;
  _ShortformMediaPhase _mediaPhase = _ShortformMediaPhase.resolving;

  /// 화면 로드 세대 토큰(§4-4-B viewLoadGeneration) — 재시도가 세대를
  /// 전진시키면 이전 세대의 늦은 응답(해석·초기화 완료)은 폐기된다.
  /// 리졸버 내부의 resolverRequestEpoch 와는 다른 층이다.
  int _viewLoadGeneration = 0;

  ShortformMediaUrlResolver get _resolver =>
      widget.mediaResolver ?? sharedShortformMediaUrlResolver;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _comments =
        widget.read.comments(CommunityPostType.shortform, widget.post.id);
    _loadReactionState();
    _loadMedia();
    // 상세 진입 시 조회수 +1(진입당 1회). RPC 부재 시 조용히 무시.
    widget.write.incrementShortformView(widget.post.id);
  }

  /// 저장값을 리졸버로 해석해 재생을 준비한다. ★ build 중 진입 금지 —
  /// initState 와 재시도([retryMedia])에서만 호출한다(§5-2).
  ///
  /// 늦은 이전 응답이 최신 시도를 덮지 않도록 시작 시 세대를 전진시키고,
  /// 각 await 뒤에서 세대·mounted 를 재확인한다. 기존 컨트롤러는 새 시도
  /// 전에 dispose 후 교체한다(§5-4).
  Future<void> _loadMedia({bool forceRefresh = false}) async {
    final int gen = ++_viewLoadGeneration;
    final ShortformVideoController? old = _video;
    _video = null;
    if (_mediaPhase != _ShortformMediaPhase.resolving) {
      setState(() => _mediaPhase = _ShortformMediaPhase.resolving);
    }
    if (old != null) await old.dispose();

    final ShortformMediaResolution res = await _resolver
        .resolve(widget.post.videoUrl, forceRefresh: forceRefresh);
    if (!mounted || gen != _viewLoadGeneration) return; // 늦은 응답 폐기

    switch (res.status) {
      case ShortformMediaStatus.absent:
        setState(() => _mediaPhase = _ShortformMediaPhase.noMedia);
        return;
      case ShortformMediaStatus.invalidReference:
        // 참조 손상은 재시도해도 결과가 같다 — 재시도 없는 실패 UI(§5-4).
        setState(() => _mediaPhase = _ShortformMediaPhase.invalidReference);
        return;
      case ShortformMediaStatus.failed:
        setState(() => _mediaPhase = _ShortformMediaPhase.failed);
        return;
      case ShortformMediaStatus.resolved:
        break;
    }

    final ShortformVideoController video =
        widget.videoControllerFactory(res.uri!);
    _video = video; // await 전에 보관 — dispose 가 반드시 해제하도록
    setState(() => _mediaPhase = _ShortformMediaPhase.initializing);
    try {
      await video.initialize();
      if (!mounted || gen != _viewLoadGeneration) return; // 소유권 이전됨
      setState(() => _mediaPhase = _ShortformMediaPhase.ready);
    } catch (_) {
      // 초기화 실패는 화면을 막지 않는다 — 실패 컨트롤러를 즉시 해제하고
      // 수동 재시도로 수렴(크래시 금지).
      if (!mounted || gen != _viewLoadGeneration) return;
      _video = null;
      await video.dispose();
      if (!mounted || gen != _viewLoadGeneration) return;
      setState(() => _mediaPhase = _ShortformMediaPhase.failed);
    }
  }

  /// 미디어 재로드 진입점 — 리졸버 캐시를 강제 무효화(forceRefresh)하고 새
  /// 세대로 다시 시도한다. 테스트가 세대 폐기 계약 검증에 직접 호출한다.
  Future<void> retryMedia() => _loadMedia(forceRefresh: true);

  /// 재시도 버튼 탭 — failed 상태에서만 1탭 = 정확히 1회 새 시도(연타 가드:
  /// 첫 탭이 동기적으로 resolving 으로 바꿔 이후 탭은 무시된다).
  void _onRetryTap() {
    if (_mediaPhase != _ShortformMediaPhase.failed) return;
    retryMedia();
  }

  /// 현재 사용자의 기존 숏폼 반응(좋아요/스크랩)을 로드해 초기 상태에 반영(게시판과 동일 패턴).
  Future<void> _loadReactionState() async {
    try {
      final Set<String> liked = await widget.read
          .myShortformReactionIds(CommunityWriteRepository.reactionLike);
      final Set<String> scrap = await widget.read
          .myShortformReactionIds(CommunityWriteRepository.reactionScrap);
      if (!mounted) return;
      setState(() {
        _liked = liked.contains(widget.post.id);
        _scrapped = scrap.contains(widget.post.id);
      });
    } catch (_) {
      // 반응 상태 조회 실패는 화면을 막지 않는다(기본 미반응).
    }
  }

  @override
  void dispose() {
    _video?.dispose(); // ★ 재생 자원 해제(네이티브 플레이어 누수 방지)
    _input.dispose();
    super.dispose();
  }

  /// 영상 탭 → 재생/일시정지 토글.
  Future<void> _togglePlay() async {
    final ShortformVideoController? video = _video;
    if (video == null || _mediaPhase != _ShortformMediaPhase.ready) return;
    if (video.isPlaying) {
      await video.pause();
    } else {
      await video.play();
    }
    if (!mounted) return;
    setState(() {}); // 재생/일시정지 오버레이 갱신
  }

  Future<void> _toggleLike() async {
    final bool next = !_liked;
    setState(() {
      _liked = next;
      _likeCount += next ? 1 : -1;
    });
    try {
      await widget.write.toggleShortformReaction(
        shortformId: widget.post.id,
        type: CommunityWriteRepository.reactionLike,
        on: next,
      );
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
      await widget.write.toggleShortformReaction(
        shortformId: widget.post.id,
        type: CommunityWriteRepository.reactionScrap,
        on: next,
      );
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
        targetType: 'shortform',
        targetId: widget.post.id,
        reason: reason,
      );
      _snack('신고가 접수되었어요. 운영팀이 검토할게요.');
    } catch (e) {
      _snack('신고 접수에 실패했어요. ${friendlyError(e)}');
    }
  }

  /// 댓글 신고 → content_reports(target_type='community_comment').
  Future<void> _reportComment(String commentId) async {
    final String? reason = await showReportSheet(context);
    if (reason == null) return;
    try {
      await widget.write.report(
        targetType: 'community_comment',
        targetId: commentId,
        reason: reason,
      );
      _snack('신고가 접수되었어요. 운영팀이 검토할게요.');
    } catch (e) {
      _snack('신고 접수에 실패했어요. ${friendlyError(e)}');
    }
  }

  /// 숏폼 작성자 차단 → 성공 시 상세를 닫아 목록으로(목록은 재조회 시 숨겨짐).
  Future<void> _blockPostAuthor() async {
    final bool blocked = await confirmAndBlockAuthor(
      context,
      table: 'shortform_posts',
      contentId: widget.post.id,
    );
    if (blocked && mounted) Navigator.of(context).pop(true);
  }

  /// 댓글 작성자 차단 → 성공 시 댓글 목록 재조회.
  Future<void> _blockCommentAuthor(String commentId) async {
    final bool blocked = await confirmAndBlockAuthor(
      context,
      table: 'community_comments',
      contentId: commentId,
    );
    if (blocked && mounted) {
      setState(() {
        _comments =
            widget.read.comments(CommunityPostType.shortform, widget.post.id);
      });
    }
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
        postType: CommunityPostType.shortform,
        postId: widget.post.id,
        body: body,
      );
      if (!mounted) return; // ★ await 중 화면이 닫혔으면 상태 갱신 금지
      _input.clear();
      setState(() {
        _comments =
            widget.read.comments(CommunityPostType.shortform, widget.post.id);
      });
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
    final ShortformPost p = widget.post;
    return Scaffold(
      appBar: AppBar(
        title: const Text('숏폼'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: '더보기',
            onSelected: (String v) {
              if (v == 'block') _blockPostAuthor();
            },
            itemBuilder: (BuildContext ctx) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'block', child: Text('이 사용자 차단')),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                // 영상 영역: 재생 준비 완료 시 플레이어(탭=재생/일시정지),
                // 해석·초기화 중엔 썸네일(9:16) 배경, 실패·영상 없음은
                // 명시적 문구 폴백(실패만 수동 재시도 제공).
                _videoArea(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          if (p.authorRole == 'mentor')
                            const AppBadge(label: '멘토', tinted: true),
                          if (p.authorRole == 'mentor')
                            const SizedBox(width: 6),
                          Text(p.authorName, style: AppType.caption),
                          const Spacer(),
                          Text('조회 ${p.viewCount}', style: AppType.caption),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.titleBody),
                      Text(p.title, style: AppType.title),
                      if (p.description?.trim().isNotEmpty == true) ...<Widget>[
                        const SizedBox(height: AppSpacing.titleBody),
                        Text(p.description!.trim(), style: AppType.body),
                      ],
                      const SizedBox(height: AppSpacing.s16),
                      ReactionBar(
                        liked: _liked,
                        scrapped: _scrapped,
                        likeCount: _likeCount,
                        commentCount: 0,
                        onToggleLike: _toggleLike,
                        onToggleScrap: _toggleScrap,
                        onReport: _report,
                      ),
                      const Divider(height: 28, color: ColorTokens.border),
                      _commentList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  /// 영상 영역 — 단계별 렌더(§5-2). 해석·초기화 중엔 썸네일 배경,
  /// noMedia/failed/invalidReference 는 명시적 문구 폴백, ready 는 플레이어.
  Widget _videoArea() {
    final ShortformVideoController? video = _video;
    if (_mediaPhase == _ShortformMediaPhase.ready && video != null) {
      final double ratio = video.aspectRatio > 0 ? video.aspectRatio : 9 / 16;
      return AspectRatio(
        aspectRatio: ratio,
        child: GestureDetector(
          onTap: _togglePlay,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              video.buildPlayer(),
              // 일시정지 상태에서만 재생 어포던스 오버레이(재생 중엔 화면만).
              // 탭은 아래 GestureDetector 가 받도록 오버레이는 히트테스트 제외.
              if (!video.isPlaying)
                const IgnorePointer(
                  child: Center(
                    child: Icon(Icons.play_circle_fill,
                        size: 64, color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    switch (_mediaPhase) {
      case _ShortformMediaPhase.resolving:
        return _mediaBackdrop(
            key: const ValueKey<String>('sf-media-resolving'));
      case _ShortformMediaPhase.initializing:
        return _mediaBackdrop(
            key: const ValueKey<String>('sf-media-initializing'));
      case _ShortformMediaPhase.noMedia:
        // 영상이 실제로 없는 행 — 실패가 아니므로 재시도를 권하지 않는다.
        return _mediaFallback('영상이 준비되지 않았어요.', showRetry: false);
      case _ShortformMediaPhase.invalidReference:
        // 참조 손상 — 재시도해도 결과가 같아 재시도 버튼을 노출하지 않는다.
        return _mediaFallback('영상을 불러오지 못했어요.', showRetry: false);
      case _ShortformMediaPhase.failed:
        return _mediaFallback('영상을 불러오지 못했어요.', showRetry: true);
      case _ShortformMediaPhase.ready:
        // ready 인데 컨트롤러가 없으면(방어) 실패 폴백과 동일 취급.
        return _mediaFallback('영상을 불러오지 못했어요.', showRetry: true);
    }
  }

  /// 해석·초기화 중 배경 — 썸네일이 있으면 표시, 없으면 중립 플레이스홀더.
  Widget _mediaBackdrop({Key? key}) {
    return AspectRatio(
      key: key,
      aspectRatio: 9 / 16,
      child: ThumbnailView(url: widget.post.thumbnailUrl),
    );
  }

  /// 실패·영상 없음 폴백 — 중립 영상 배경 위 안내 문구(+ 필요 시 수동 재시도).
  /// 자동 무한 재시도는 하지 않는다(§5-4).
  Widget _mediaFallback(String message, {required bool showRetry}) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ThumbnailView(url: widget.post.thumbnailUrl),
          ColoredBox(
            color: const Color(0x66000000), // 문구 대비용 스크림
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.videocam_off_outlined,
                      size: 40, color: Colors.white70),
                  const SizedBox(height: 8),
                  Text(message,
                      style: AppType.caption.copyWith(color: Colors.white)),
                  if (showRetry) ...<Widget>[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _onRetryTap,
                      style:
                          TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
