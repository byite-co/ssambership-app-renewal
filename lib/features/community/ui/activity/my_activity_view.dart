import 'package:flutter/material.dart';

import '../../../../app/app_navigation.dart';
import '../../../../app/app_route_paths.dart';
import '../../../../design/spacing_tokens.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/empty_state.dart';
import '../../data/community_models.dart';
import '../../data/community_read_repository.dart';
import '../../data/community_write_repository.dart';
import '../board/board_detail_screen.dart';
import '../widgets/board_post_card.dart';
import '../../../../shared/errors/friendly_error.dart';

/// 내 활동 탭 — 내가 쓴 글 / 좋아요 / 스크랩(읽기). 카드 탭 → 상세.
///
/// §4-3 최신성: 관리자 숨김·복구는 앱 밖에서 일어나므로 이 목록도 board 탭과 같은
/// 3경로(앱 복귀 resume · pull-to-refresh · 상세에서 변경 후 복귀)로 재조회한다.
/// 재조회는 세대 토큰(`_generation`)을 지나 늦은 이전 응답을 폐기한다.
class MyActivityView extends StatefulWidget {
  const MyActivityView({super.key, required this.read, required this.write});

  final CommunityReadRepository read;
  final CommunityWriteRepository write;

  @override
  State<MyActivityView> createState() => MyActivityViewState();
}

/// 상태를 공개해 바깥(커뮤니티 화면)에서 앱 복귀 시 [reload] 로 재조회한다.
class MyActivityViewState extends State<MyActivityView> {
  MyActivity? _data;
  Object? _error;
  bool _loading = true;

  /// 늦게 도착한 이전 재조회 응답 폐기용 세대 토큰.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 첫 페이지부터 다시 로드(앱 복귀·PTR·상세 변경 복귀 공용).
  Future<void> reload() => _load();

  Future<void> _load() {
    final int gen = ++_generation;
    if (_data == null) {
      // 첫 로드에서만 전체 로딩 인디케이터 — 재조회는 직전 화면을 유지한다.
      _loading = true;
    }
    return widget.read.myActivity().then((MyActivity data) {
      if (!mounted || gen != _generation) return; // 늦은 이전 응답 폐기
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    }).catchError((Object e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        // 마지막 정상 스냅샷이 있으면 지우지 않는다(첫 로드 실패만 오류 화면).
        if (_data == null) _error = e;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final Object? error = _error;
    if (error != null && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('내 활동을 불러오지 못했어요.\n${friendlyError(error)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ColorTokens.danger)),
        ),
      );
    }
    final MyActivity a = _data ?? const MyActivity();
    // §4: 외부(웹·관리자) 변경 반영용 pull-to-refresh — 세대 토큰이 있어
    // 늦은 응답이 최신 목록을 덮지 않는다. 빈 상태에서도 당길 수 있어야 한다.
    return RefreshIndicator(
      onRefresh: _load,
      child: a.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const <Widget>[
                SizedBox(
                  height: 360,
                  child: EmptyState(
                    icon: Icons.history_outlined,
                    title: '아직 활동이 없어요',
                    message: '글에 좋아요·스크랩하거나 웹에서 글을 쓰면 여기에 모여요.',
                  ),
                ),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH, 12, AppSpacing.screenH, 24),
              children: <Widget>[
                _group('내가 쓴 글', a.myPosts),
                _group('좋아요한 글', a.liked),
                _group('스크랩한 글', a.scrapped),
              ],
            ),
    );
  }

  Widget _group(String title, List<BoardPost> posts) {
    if (posts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 6, bottom: 8),
          child: Text(title, style: AppType.caption),
        ),
        for (final BoardPost p in posts) ...<Widget>[
          BoardPostCard(post: p, onOpen: () => _open(p)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<void> _open(BoardPost post) async {
    // §4-3: 상세에서 변경(좋아요·스크랩 취소·차단·삭제 등, pop true)이 있었을 때만
    // 재조회 — 내 활동 목록의 구성 자체가 바뀌므로 board 탭과 동일 계약을 쓴다.
    final bool? changed = await AppNavigation.push<bool>(
      context,
      AppRoutePaths.boardPost(post.id),
      fallbackBuilder: (_) => BoardDetailScreen(
        post: post,
        read: widget.read,
        write: widget.write,
      ),
    );
    if (changed == true && mounted) await _load();
  }
}
