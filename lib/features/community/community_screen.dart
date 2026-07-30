import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
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
/// ★ S2-2(앱 계약 §6.5): 커뮤니티 신규 작성은 **승인 멘토 전용** — 게시판
///   '작성' CTA 는 멘토에게만 노출한다(학생 CTA 제거). 승인 여부 최종 판정은
///   서버(F4 — ROLE_NOT_MENTOR/MENTOR_NOT_APPROVED 구분)가 한다.
///   숏폼 '작성'도 멘토 한정 인앱 WebView(웹 작성기 계약,
///   ShortformComposeScreen) — 진입점은 숏폼 피드(ShortformFeedView)에 있다.
///   네이티브 숏폼 INSERT 는 없다. 기존 학생 글은 열람·본인 삭제가 유지된다.
///   레포는 테스트에서 fake 로 주입할 수 있게 optional 로 받는다(기본은 실제).
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    this.read = const CommunityReadRepository(),
    this.write = const CommunityWriteRepository(),
    this.roleOf = _defaultRoleOf,
  });

  final CommunityReadRepository read;
  final CommunityWriteRepository write;

  /// 현재 역할 판정(테스트 주입용). 기본은 [AuthService] 단일 소스.
  final AppRole Function() roleOf;

  static AppRole _defaultRoleOf() => AuthService.instance.currentRole;

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
    // 작성 자격: 승인 멘토 전용(§6.5) — 학생·게스트는 CTA 자체를 보지 않는다.
    // (관리자는 앱 진입 자체가 차단 — auth_service.computeAccess.)
    final bool showComposeFab =
        _tab.index == _boardTab && widget.roleOf() == AppRole.mentor;
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
      // 게시판 탭 + 멘토일 때만 노출. 역할색은 AppAccent 경유.
      floatingActionButton: showComposeFab
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
