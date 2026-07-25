import 'package:flutter/material.dart';

import '../../design/role_accent.dart';
import '../../design/tokens/color_tokens.dart';
import '../../design/typography_tokens.dart';
import 'data/community_read_repository.dart';
import 'data/community_write_repository.dart';
import 'ui/activity/my_activity_view.dart';
import 'ui/board/board_list_view.dart';
import 'ui/board/board_write_screen.dart';
import 'ui/shortform/shortform_feed_view.dart';

/// 커뮤니티 탭. 상단 탭(숏폼 / 게시판 / 내 활동). HomeShell 이 바깥 AppBar/하단탭 제공.
///
/// ★ 게시판 '글쓰기'는 앱에서 가능(즉시 공개). 숏폼 '작성'은 멘토 한정
///   인앱 WebView(웹 작성기 계약, ShortformComposeScreen)로 제공 — 진입점은
///   숏폼 피드(ShortformFeedView)에 있다. 네이티브 숏폼 INSERT 는 없다.
///   레포는 테스트에서 fake 로 주입할 수 있게 optional 로 받는다(기본은 실제).
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    this.read = const CommunityReadRepository(),
    this.write = const CommunityWriteRepository(),
  });

  final CommunityReadRepository read;
  final CommunityWriteRepository write;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _boardTab = 1;

  late final TabController _tab;
  final GlobalKey<BoardListViewState> _boardKey =
      GlobalKey<BoardListViewState>();
  final GlobalKey<ShortformFeedViewState> _shortformKey =
      GlobalKey<ShortformFeedViewState>();
  final GlobalKey<MyActivityViewState> _activityKey =
      GlobalKey<MyActivityViewState>();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // 게시판 탭에서만 글쓰기 FAB 노출 → 탭 전환 시 리빌드.
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
    // §4: 관리자 숨김·복구 등 외부 변경 반영 — 앱 복귀(resumed) 시 목록 재조회.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 세대 토큰이 있는 paginator.refresh 라 무한 새로고침·stale 덮어쓰기 없음.
      // §4-3: 관리자 숨김·복구는 board 만의 일이 아니다 — 3개 탭을 모두 재조회한다
      // (살아 있는 탭만 반응: currentState 가 null 이면 다음 진입 시 어차피 fresh).
      _boardKey.currentState?.reload();
      _shortformKey.currentState?.reload();
      _activityKey.currentState?.reload();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tab.dispose();
    super.dispose();
  }

  /// 게시판 글쓰기 → 성공(pop true) 시 목록 새로고침.
  Future<void> _openWrite() async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => BoardWriteScreen(write: widget.write),
      ),
    );
    if (created == true && mounted) {
      await _boardKey.currentState?.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('글이 등록됐어요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool onBoardTab = _tab.index == _boardTab;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: <Widget>[
          TabBar(
            controller: _tab,
            labelColor: AppAccent.of(context).accent,
            unselectedLabelColor: ColorTokens.secondary,
            indicatorColor: AppAccent.of(context).accent,
            labelStyle: AppType.body,
            tabs: const <Widget>[
              Tab(text: '숏폼'),
              Tab(text: '게시판'),
              Tab(text: '내 활동'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: <Widget>[
                ShortformFeedView(
                    key: _shortformKey, read: widget.read, write: widget.write),
                BoardListView(
                    key: _boardKey, read: widget.read, write: widget.write),
                MyActivityView(
                    key: _activityKey, read: widget.read, write: widget.write),
              ],
            ),
          ),
        ],
      ),
      // 게시판 탭에서만 노출. 역할색(학생 파랑/멘토 초록)은 AppAccent 경유.
      floatingActionButton: onBoardTab
          ? FloatingActionButton.extended(
              onPressed: _openWrite,
              backgroundColor: AppAccent.of(context).accent,
              foregroundColor: AppAccent.of(context).onAccent,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('작성'),
            )
          : null,
    );
  }
}
