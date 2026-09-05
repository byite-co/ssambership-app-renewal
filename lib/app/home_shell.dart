import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_service.dart' show AppRole;
import '../core/refresh/data_refresh_bus.dart';
import '../design/role_theme.dart' as design;
import '../design/tokens/app_spacing.dart';
import '../design/widgets/app_background.dart';
import '../design/widgets/app_blocks.dart';
import '../design/widgets/app_empty_state.dart';
import '../design/widgets/app_page.dart';
import '../design/widgets/glass_bars.dart';
import '../features/community/community_screen.dart';
import '../features/individual_question/individual_question_tab_screen.dart';
import '../features/mentor_console/ui/mentor_settlement_screen.dart';
import '../features/mentors/mentors_screen.dart';
import '../features/mypage/data/mypage_models.dart';
import '../features/mypage/ui/sections/mentor_dashboard_section.dart';
import '../features/notifications/data/notification_badge_controller.dart'
    show notificationBadgeLabel;
import '../features/notifications/notifications_screen.dart';
import '../features/question_room/question_room_screen.dart';
import '../shared/constants/app_constants.dart';
import '../shared/errors/friendly_error.dart';
import '../shared/widgets/screen_visibility.dart';
import '../shared/widgets/withdrawal_pending_banner.dart';
import 'app_navigation.dart';
import 'app_route_paths.dart';
import 'app_scope.dart';
import 'app_tabs.dart';
import 'async_route_loader.dart';
import 'entry_guard.dart';
import 'routes/mypage_routes.dart';

/// 역할별 5탭 셸.
///
/// 운영 라우터에서는 [StatefulNavigationShell.currentIndex]가 선택 상태의 정본이고
/// 각 branch Navigator가 탭별 상태를 보존한다. [navigationShell]이 없는 경우는
/// 기존 직접-pump 테스트를 위한 작은 IndexedStack 폴백이다.
///
/// 껍데기(배경·유리 앱바·유리 탭바)는 [HomeShellChrome] 이 그린다 — 탭 골든이
/// 같은 껍데기로 그려지도록 분리했다(A-6b).
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.navigationShell,
    this.location,
    this.myPageLoaderOverride,
  });

  /// 운영에서는 `StatefulShellRoute.indexedStack`이 제공한다.
  final StatefulNavigationShell? navigationShell;

  /// 현재 matched URL. AppBar 제목과 shared branch의 deep-only 표면 판정에 쓴다.
  final String? location;

  /// 직접-pump 테스트용 마이페이지 데이터 주입. 운영에서는 null이다.
  final Future<MyPageData> Function()? myPageLoaderOverride;

  /// 역할별 하단 탭(아이콘은 v3 아웃라인 세트, 라벨은 [AppConstants] 정본).
  static List<GlassTabItem> tabItemsFor(AppRole role) {
    final List<String> labels = role == AppRole.mentor
        ? AppConstants.mentorBottomTabLabels
        : AppConstants.studentBottomTabLabels;
    final List<IconData> icons = role == AppRole.mentor
        ? const <IconData>[
            Icons.forum_outlined,
            Icons.chat_bubble_outline,
            Icons.account_balance_wallet_outlined,
            Icons.groups_outlined,
            Icons.notifications_none,
          ]
        : const <IconData>[
            Icons.forum_outlined,
            Icons.chat_bubble_outline,
            Icons.person_search_outlined,
            Icons.groups_outlined,
            Icons.notifications_none,
          ];
    return <GlassTabItem>[
      for (int i = 0; i < labels.length; i++)
        GlassTabItem(icon: icons[i], label: labels[i]),
    ];
  }

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final AppDependencies _deps;
  late int _fallbackIndex;
  final List<bool> _fallbackBuilt = List<bool>.filled(5, false);

  static const List<_HomeTabDestination> _studentTabs = <_HomeTabDestination>[
    _HomeTabDestination(
      location: AppTab.questionRoom,
      fallbackPage: QuestionRoomScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.individualQuestion,
      fallbackPage: IndividualQuestionTabScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.mentors,
      fallbackPage: MentorsScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.community,
      fallbackPage: CommunityScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.notifications,
      fallbackPage: NotificationsScreen(),
      hasNotificationBadge: true,
    ),
  ];

  static const List<_HomeTabDestination> _mentorTabs = <_HomeTabDestination>[
    _HomeTabDestination(
      location: AppTab.questionRoom,
      fallbackPage: QuestionRoomScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.individualQuestion,
      fallbackPage: IndividualQuestionTabScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.settlements,
      fallbackPage: MentorSettlementsTabBody(),
    ),
    _HomeTabDestination(
      location: AppTab.community,
      fallbackPage: CommunityScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.notifications,
      fallbackPage: NotificationsScreen(),
      hasNotificationBadge: true,
    ),
  ];

  AppRole get _role => _deps.auth.currentRole;

  List<_HomeTabDestination> get _tabs =>
      _role == AppRole.mentor ? _mentorTabs : _studentTabs;

  @override
  void initState() {
    super.initState();
    _deps = AppScope.of(context);
    _fallbackIndex = _deps.auth.isGuest ? 2 : 0;
    _fallbackBuilt[_fallbackIndex] = true;
    TabNavigator.request.addListener(_onTabRequest);
    if (!_deps.auth.isGuest) {
      _deps.notificationBadge.refresh();
    }
  }

  @override
  void dispose() {
    TabNavigator.request.removeListener(_onTabRequest);
    _deps.notificationBadge.clear();
    super.dispose();
  }

  /// 경로 요청을 처리한 뒤 null로 되돌려 같은 경로 재요청도 알린다.
  void _onTabRequest() {
    final String? location = TabNavigator.request.value;
    if (location == null) return;
    TabNavigator.request.value = null;
    if (location == AppTab.myPage) {
      _openMyPage();
      return;
    }
    _selectLocation(location);
  }

  void _selectLocation(String location) {
    if (_deps.auth.isGuest && !EntryGuard.isTabAllowedForGuest(location)) {
      context.go(AppRoutePaths.loginWithNotice('login_required'));
      return;
    }

    if (location == AppTab.notifications) {
      DataRefreshBus.bumpNotifications();
    }
    if (location == AppTab.questionRoom) {
      DataRefreshBus.bumpQuestionRooms();
    }

    final StatefulNavigationShell? shell = widget.navigationShell;
    if (shell != null) {
      final int? branchIndex = _branchIndexFor(location);
      if (branchIndex == null) return;

      // branch 2는 역할별 `/mentors`와 `/settlements` URL을 공유한다.
      // 버튼은 정확한 canonical URL로 보내고, 역할에 맞지 않는 형제 URL은
      // AppRouter가 정규화한다. 이후에는 branch의 마지막 상태를 복원한다.
      if (branchIndex == 2) {
        context.go(location);
      } else {
        shell.goBranch(
          branchIndex,
          initialLocation: branchIndex == shell.currentIndex,
        );
      }
      return;
    }

    // 작은 widget-test/골든용 폴백. 운영 선택 상태에는 사용되지 않는다.
    final int index = _tabs.indexWhere(
      (_HomeTabDestination tab) => tab.location == location,
    );
    if (index < 0) return;
    setState(() {
      _fallbackIndex = index;
      _fallbackBuilt[index] = true;
    });
  }

  Future<void> _openSettlementHub() => AppNavigation.push<void>(
        context,
        AppRoutePaths.settlementHistory,
        fallbackBuilder: (_) => const MentorSettlementScreen(),
      );

  Future<void> _openMyPage() async {
    if (_deps.auth.isGuest) {
      context.go(AppRoutePaths.loginWithNotice('login_required'));
      return;
    }
    final String? location = await AppNavigation.push<String>(
      context,
      AppRoutePaths.myPage,
      fallbackBuilder: (_) =>
          MyPageRoutePage(loaderOverride: widget.myPageLoaderOverride),
    );
    if (!mounted || location == null) return;
    _selectLocation(location);
  }

  @override
  Widget build(BuildContext context) {
    final List<_HomeTabDestination> tabs = _tabs;
    final StatefulNavigationShell? shell = widget.navigationShell;
    final int selectedIndex = shell?.currentIndex ?? _fallbackIndex;
    final String activeLocation =
        widget.location ?? tabs[selectedIndex].location;
    final bool shellRouteVisible = ModalRoute.of(context)?.isCurrent ?? true;

    final bool showSettlementHub =
        _role == AppRole.mentor && activeLocation == AppTab.settlements;

    return ValueListenableBuilder<int?>(
      valueListenable: _deps.notificationBadge.count,
      builder: (BuildContext context, int? count, Widget? body) {
        final String? badge = notificationBadgeLabel(count);
        final List<GlassTabItem> base = HomeShell.tabItemsFor(_role);
        return HomeShellChrome(
          title: _titleFor(activeLocation, base[selectedIndex].label),
          actions: <Widget>[
            // A-4a: 정산 탭(멘토)에서만 정산 허브(/settlements/history) 진입.
            if (showSettlementHub)
              IconButton(
                tooltip: MentorSettlementScreen.entryTooltip,
                icon: const Icon(Icons.receipt_long_rounded),
                onPressed: _openSettlementHub,
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _ProfileCircleButton(onTap: _openMyPage),
            ),
          ],
          tabs: <GlassTabItem>[
            for (int i = 0; i < base.length; i++)
              GlassTabItem(
                icon: base[i].icon,
                label: base[i].label,
                badgeLabel: tabs[i].hasNotificationBadge ? badge : null,
              ),
          ],
          selectedIndex: selectedIndex,
          onSelected: (int index) => _selectLocation(tabs[index].location),
          body: body!,
        );
      },
      child: Column(
        children: <Widget>[
          const WithdrawalPendingBanner(),
          Expanded(
            child: shell == null
                ? IndexedStack(
                    index: selectedIndex,
                    children: <Widget>[
                      for (int i = 0; i < tabs.length; i++)
                        ScreenVisibility(
                          visible: i == selectedIndex,
                          child: _fallbackBuilt[i]
                              ? tabs[i].fallbackPage
                              : const SizedBox.shrink(),
                        ),
                    ],
                  )
                : _HomeTabVisibilityScope(
                    activeIndex: selectedIndex,
                    shellRouteVisible: shellRouteVisible,
                    child: shell,
                  ),
          ),
        ],
      ),
    );
  }

  static int? _branchIndexFor(String location) {
    switch (location) {
      case AppTab.questionRoom:
        return 0;
      case AppTab.individualQuestion:
        return 1;
      case AppTab.mentors:
      case AppTab.settlements:
        return 2;
      case AppTab.community:
        return 3;
      case AppTab.notifications:
        return 4;
    }
    return null;
  }

  static String _titleFor(String location, String fallback) {
    switch (location) {
      case AppTab.questionRoom:
        return '질문방';
      case AppTab.individualQuestion:
        return '개별질문';
      case AppTab.mentors:
        return '멘토 찾기';
      case AppTab.settlements:
        return '정산';
      case AppTab.community:
        return '커뮤니티';
      case AppTab.notifications:
        return '알림';
    }
    return fallback;
  }
}

/// 홈 셸 껍데기 — 배경 그라디언트 + 유리 앱바 + 유리 탭바.
///
/// 탭 본문은 [AppPageBody] 규칙(앱바 아래에서 뷰포트 시작, 넘친 스크롤은 앱바 뒤로)을
/// 그대로 따르고, 탭바 뒤까지 본문이 늘어나므로 스크롤 본문은
/// [AppPage.contentPadding] 으로 하단 여백을 잡는다. 탭 골든도 이 위젯으로 그린다.
class HomeShellChrome extends StatelessWidget {
  const HomeShellChrome({
    super.key,
    required this.title,
    required this.body,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.actions = const <Widget>[],
  });

  final String title;
  final Widget body;
  final List<GlassTabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        extendBody: true,
        appBar: GlassAppBar(
          title: Text(title),
          automaticallyImplyLeading: false,
          actions: actions,
        ),
        body: AppPageBody(child: body),
        bottomNavigationBar: GlassTabBar(
          items: tabs,
          selectedIndex: selectedIndex,
          onSelected: onSelected,
        ),
      ),
    );
  }
}

/// Shell branch의 resume 가시성 게이트.
///
/// indexedStack은 각 Navigator를 계속 살려 두므로, URL에서 계산한 활성 branch만
/// 보이는 것으로 표시해 백그라운드 복귀 시 숨은 화면의 동시 재조회를 막는다.
class HomeTabBranch extends StatelessWidget {
  const HomeTabBranch({
    super.key,
    required this.branchIndex,
    required this.child,
  });

  final int branchIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final _HomeTabVisibilityScope? scope =
        _HomeTabVisibilityScope.maybeOf(context);
    return ScreenVisibility(
      visible: scope == null ||
          (scope.activeIndex == branchIndex && scope.shellRouteVisible),
      child: child,
    );
  }
}

class _HomeTabVisibilityScope extends InheritedWidget {
  const _HomeTabVisibilityScope({
    required this.activeIndex,
    required this.shellRouteVisible,
    required super.child,
  });

  final int activeIndex;
  final bool shellRouteVisible;

  static _HomeTabVisibilityScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HomeTabVisibilityScope>();

  @override
  bool updateShouldNotify(_HomeTabVisibilityScope oldWidget) =>
      activeIndex != oldWidget.activeIndex ||
      shellRouteVisible != oldWidget.shellRouteVisible;
}

class _HomeTabDestination {
  const _HomeTabDestination({
    required this.location,
    required this.fallbackPage,
    this.hasNotificationBadge = false,
  });

  final String location;
  final Widget fallbackPage;
  final bool hasNotificationBadge;
}

/// 멘토 탭은 새 정산 화면을 만들지 않고 MyPage의 기존 답변·정산 요약을 재사용한다.
class MentorSettlementsTabBody extends StatelessWidget {
  const MentorSettlementsTabBody({super.key});

  @override
  Widget build(BuildContext context) {
    return AsyncRouteLoader<MentorDashboard>(
      load: (AppDependencies dependencies) async =>
          (await dependencies.myPage.load()).mentor,
      loadingBuilder: (_) => const AppLoadingView(cards: 1),
      notFoundBuilder: (_) => const AppEmptyState(
        icon: Icons.receipt_long_rounded,
        title: '정산 요약을 불러올 수 없어요.',
        description: '잠시 후 다시 확인해 주세요.',
      ),
      errorBuilder: (BuildContext context, Object error, VoidCallback retry) =>
          AppErrorView(
        title: '정산 요약을 불러오지 못했어요.',
        message: friendlyError(error),
        onRetry: retry,
      ),
      builder: (
        BuildContext context,
        MentorDashboard dashboard,
        AppDependencies dependencies,
      ) =>
          ListView(
        clipBehavior: Clip.none,
        padding: AppPage.contentPadding(context, top: AppSpacing.s16),
        children: <Widget>[
          MentorDashboardSection(
            data: dashboard,
            onGoToQuestions: () => TabNavigator.go(AppTab.questionRoom),
            // 정산 화면 자체 — 정산 안내 카드는 띄우지 않는다(정산 허브 아이콘이 위에 있다).
            showPayoutNotice: false,
          ),
        ],
      ),
      notFoundMessage: '정산 요약을 불러올 수 없어요.',
      errorMessage: '정산 요약을 불러오지 못했어요.',
    );
  }
}

class _ProfileCircleButton extends StatelessWidget {
  const _ProfileCircleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final design.RoleTheme roleTheme = design.RoleTheme.of(context);
    return Semantics(
      button: true,
      label: AppConstants.myPageTitle,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: roleTheme.tint,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person_rounded, size: 22, color: roleTheme.color),
        ),
      ),
    );
  }
}
