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
import '../widgets/block_author_action.dart';
import '../widgets/comment_tile.dart';
import '../widgets/content_policy_gate.dart';
import '../widgets/reaction_bar.dart';
import '../widgets/report_sheet.dart';
import '../widgets/thumbnail_view.dart';
import 'shortform_video_port.dart';
import '../../../../shared/errors/friendly_error.dart';

/// 숏폼 상세 — 세로 영상 재생(video_player, 탭=재생/일시정지) + 반응 + 댓글.
/// videoUrl 이 없거나(http/https 아님 포함) 초기화 실패 시 썸네일 폴백.
/// 작성은 '댓글'만.
class ShortformDetailScreen extends StatefulWidget {
  const ShortformDetailScreen({
    super.key,
    required this.post,
    required this.read,
    required this.write,
    this.videoControllerFactory = createShortformVideoController,
  });

  final ShortformPost post;
  final CommunityReadRepository read;
  final CommunityWriteRepository write;

  /// 재생 컨트롤러 팩토리 — 테스트에서 fake 주입(실네트워크 재생 회피).
  final ShortformVideoControllerFactory videoControllerFactory;

  @override
  State<ShortformDetailScreen> createState() => _ShortformDetailScreenState();
}

class _ShortformDetailScreenState extends State<ShortformDetailScreen> {
  final TextEditingController _input = TextEditingController();
  late Future<List<CommunityComment>> _comments;

  bool _liked = false;
  bool _scrapped = false;
  late int _likeCount;
  bool _busy = false;

  ShortformVideoController? _video;
  bool _videoReady = false;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _comments =
        widget.read.comments(CommunityPostType.shortform, widget.post.id);
    _loadReactionState();
    _initVideo();
    // 상세 진입 시 조회수 +1(진입당 1회). RPC 부재 시 조용히 무시.
    widget.write.incrementShortformView(widget.post.id);
  }

  /// videoUrl 이 유효한 http(s)면 재생 준비. 없거나 초기화 실패면 썸네일 폴백.
  Future<void> _initVideo() async {
    final Uri? url = _validVideoUrl(widget.post.videoUrl);
    if (url == null) return; // 썸네일 폴백(재생 없음)
    final ShortformVideoController video = widget.videoControllerFactory(url);
    _video = video; // await 전에 보관 — dispose 가 반드시 해제하도록
    try {
      await video.initialize();
      if (!mounted) return;
      setState(() => _videoReady = true);
    } catch (_) {
      // 재생 실패는 화면을 막지 않는다 — 썸네일 폴백(크래시 금지).
      if (!mounted) return;
      setState(() => _videoFailed = true);
    }
  }

  /// http/https 절대 URL 만 재생 대상으로 인정(그 외 null → 썸네일 폴백).
  Uri? _validVideoUrl(String? raw) {
    final String s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    final Uri? u = Uri.tryParse(s);
    if (u == null || !(u.isScheme('http') || u.isScheme('https'))) return null;
    return u;
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
    if (video == null || !_videoReady) return;
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
                // 그 외(초기화 중/URL 없음/실패)는 썸네일(9:16) 폴백.
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

  /// 영상 영역 — 준비 완료 전(초기화 중)·URL 없음·실패는 모두 썸네일 폴백.
  Widget _videoArea() {
    final ShortformVideoController? video = _video;
    if (video == null || _videoFailed || !_videoReady) {
      return AspectRatio(
        aspectRatio: 9 / 16,
        child: ThumbnailView(url: widget.post.thumbnailUrl),
      );
    }
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
