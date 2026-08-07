import 'package:flutter/material.dart';

import '../../../../design/spacing_tokens.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/widgets/chip_scroll.dart';
import '../../../../design/widgets/empty_state.dart';
import '../../data/community_labels.dart';
import '../../data/community_models.dart';
import '../../data/community_paginator.dart';
import '../../data/community_read_repository.dart';
import '../../data/community_write_repository.dart';
import '../widgets/board_post_card.dart';
import 'board_detail_screen.dart';
import '../../../../shared/errors/friendly_error.dart';

/// 게시판 탭 — 카테고리칩 필터 + 글 리스트(최신순). 카드 탭 → 상세.
/// 페이징·세대(스테일 응답 폐기)는 [CommunityPaginator] 가 관리(P2-21).
class BoardListView extends StatefulWidget {
  const BoardListView({super.key, required this.read, required this.write});

  final CommunityReadRepository read;
  final CommunityWriteRepository write;

  @override
  State<BoardListView> createState() => BoardListViewState();
}

/// 상태를 공개해 글 작성 성공 시 바깥(커뮤니티 화면)에서 [reload]로 새로고침한다.
class BoardListViewState extends State<BoardListView> {
  static const int _pageSize = 20;

  final ScrollController _scroll = ScrollController();
  late final CommunityPaginator<BoardPost> _pager;
  String? _category; // null = 전체

  @override
  void initState() {
    super.initState();
    // fetch 클로저가 현재 _category 를 읽는다 — 카테고리 전환은 refresh 로
    // 세대가 바뀌므로 이전 카테고리의 늦은 응답은 자동 폐기.
    _pager = CommunityPaginator<BoardPost>(
      fetch: (int offset, int limit) =>
          widget.read.boards(category: _category, limit: limit, offset: offset),
      pageSize: _pageSize,
    );
    _scroll.addListener(_onScroll);
    _pager.refresh();
  }

  @override
  void dispose() {
    _pager.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      _pager.loadMore();
    }
  }

  /// 첫 페이지부터 다시 로드(글 작성 직후 새 글 반영용).
  Future<void> reload() => _pager.refresh();

  void _selectCategory(String? code) {
    // setState 필수 — 칩의 selected 인덱스는 build() 에서 계산되므로, 없으면
    // 목록만 갱신되고(pager 알림) 선택 표시는 첫 칩에 고정된 채 움직이지 않는다.
    setState(() => _category = code);
    _pager.refresh(); // 세대 +1 — 이전 카테고리 응답은 도착해도 무시
  }

  @override
  Widget build(BuildContext context) {
    final List<String> labels = <String>[
      '전체',
      for (final MapEntry<String, String> e in communityCategoryOptions)
        e.value,
    ];
    final int selected = _category == null
        ? 0
        : communityCategoryOptions.indexWhere(
                (MapEntry<String, String> e) => e.key == _category) +
            1;

    return ListenableBuilder(
      listenable: _pager,
      builder: (BuildContext context, _) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: ChipScroll(
              labels: labels,
              selectedIndex: selected < 0 ? 0 : selected,
              onSelected: (int i) => _selectCategory(
                  i == 0 ? null : communityCategoryOptions[i - 1].key),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_pager.initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pager.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('글을 불러오지 못했어요.\n${friendlyError(_pager.error!)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: ColorTokens.danger)),
        ),
      );
    }
    final List<BoardPost> posts = _pager.items;
    if (posts.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_rounded,
        title: '아직 글이 없어요',
        message: '이 분류에는 글이 없어요.',
      );
    }
    // §4: 외부(웹·관리자) 변경 반영용 pull-to-refresh — 세대 토큰이 있는
    // paginator.refresh 라 늦은 응답이 최신 목록을 덮지 않는다.
    return RefreshIndicator(
      onRefresh: () => _pager.refresh(),
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH, 4, AppSpacing.screenH, 88),
        itemCount: posts.length + (_pager.hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          if (i >= posts.length) {
            // 다음 페이지 로딩 인디케이터(끝에 도달 시 자동 로드).
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return BoardPostCard(post: posts[i], onOpen: () => _open(posts[i]));
        },
      ),
    );
  }

  Future<void> _open(BoardPost post) async {
    // §4: 상세에서 댓글·반응 등 변경(pop true)이 있었을 때만 첫 페이지 재조회
    // — 카드의 댓글수·좋아요수 stale 해소(무조건 재조회로 인한 중복 호출 없음).
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BoardDetailScreen(
          post: post,
          read: widget.read,
          write: widget.write,
        ),
      ),
    );
    if (changed == true && mounted) await _pager.refresh();
  }
}
