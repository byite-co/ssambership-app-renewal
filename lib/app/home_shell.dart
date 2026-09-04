import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_service.dart' show AppRole;
import '../core/refresh/data_refresh_bus.dart';
import '../design/spacing_tokens.dart';
import '../features/community/community_screen.dart';
import '../features/individual_question/individual_question_tab_screen.dart';
import '../features/mentors/mentors_screen.dart';
import '../features/mypage/data/mypage_models.dart';
import '../features/mypage/ui/sections/mentor_dashboard_section.dart';
import '../features/notifications/data/notification_badge_controller.dart'
    show notificationBadgeLabel;
import '../features/notifications/notifications_screen.dart';
import '../features/question_room/question_room_screen.dart';
import '../shared/constants/app_constants.dart';
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
      label: '질문방',
      icon: Icons.forum_rounded,
      fallbackPage: QuestionRoomScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.individualQuestion,
      label: '개별질문',
      icon: Icons.question_answer_rounded,
      fallbackPage: IndividualQuestionTabScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.mentors,
      label: '멘토 찾기',
      icon: Icons.search_rounded,
      fallbackPage: MentorsScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.community,
      label: '커뮤니티',
      icon: Icons.groups_rounded,
      fallbackPage: CommunityScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.notifications,
      label: '알림',
      icon: Icons.notifications_rounded,
      fallbackPage: NotificationsScreen(),
      hasNotificationBadge: true,
    ),
  ];

  static const List<_HomeTabDestination> _mentorTabs = <_HomeTabDestination>[
    _HomeTabDestination(
      location: AppTab.questionRoom,
      label: '질문방',
      icon: Icons.forum_rounded,
      fallbackPage: QuestionRoomScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.individualQuestion,
      label: '개별질문',
      icon: Icons.question_answer_rounded,
      fallbackPage: IndividualQuestionTabScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.settlements,
      label: '정산',
      icon: Icons.account_balance_wallet_rounded,
      fallbackPage: MentorSettlementsTabBody(),
    ),
    _HomeTabDestination(
      location: AppTab.community,
      label: '커뮤니티',
      icon: Icons.groups_rounded,
      fallbackPage: CommunityScreen(),
    ),
    _HomeTabDestination(
      location: AppTab.notifications,
      label: '알림',
      icon: Icons.notifications_rounded,
      fallbackPage: NotificationsScreen(),
      hasNotificationBadge: true,
    ),
  ];

  List<_HomeTabDestination> get _tabs =>
      _deps.auth.currentRole == AppRole.mentor ? _mentorTabs : _studentTabs;

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

      // branch 2는 `/mentors`와 `/settlements` 두 유효 URL을 공유한다.
      // 역할별 버튼은 정확한 canonical URL로 보내고, 이후 다른 branch를
      // 오갈 때는 goBranch가 해당 Navigator의 마지막 상태를 복원한다.
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(activeLocation, tabs[selectedIndex].label)),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ProfileCircleButton(onTap: _openMyPage),
          ),
        ],
      ),
      body: Column(
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
                    child: shell,
                  ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (int index) =>
            _selectLocation(tabs[index].location),
        destinations: <NavigationDestination>[
          for (final _HomeTabDestination tab in tabs)
            NavigationDestination(
              icon: tab.hasNotificationBadge
                  ? _NotificationsTabIcon(icon: tab.icon)
                  : Icon(tab.icon),
              label: tab.label,
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
    final int? activeIndex = _HomeTabVisibilityScope.maybeActiveIndex(context);
    return ScreenVisibility(
      visible: activeIndex == null || activeIndex == branchIndex,
      child: child,
    );
  }
}

class _HomeTabVisibilityScope extends InheritedWidget {
  const _HomeTabVisibilityScope({
    required this.activeIndex,
    required super.child,
  });

  final int activeIndex;

  static int? maybeActiveIndex(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_HomeTabVisibilityScope>()
      ?.activeIndex;

  @override
  bool updateShouldNotify(_HomeTabVisibilityScope oldWidget) =>
      activeIndex != oldWidget.activeIndex;
}

class _HomeTabDestination {
  const _HomeTabDestination({
    required this.location,
    required this.label,
    required this.icon,
    required this.fallbackPage,
    this.hasNotificationBadge = false,
  });

  final String location;
  final String label;
  final IconData icon;
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
      loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
      notFoundBuilder: (_) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('정산 요약을 불러올 수 없어요.'),
        ),
      ),
      errorBuilder: (BuildContext context, Object error, VoidCallback retry) =>
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('정산 요약을 불러오지 못했어요.'),
                  const SizedBox(height: AppSpacing.s12),
                  TextButton(onPressed: retry, child: const Text('다시 시도')),
                ],
              ),
            ),
          ),
      builder:
          (
            BuildContext context,
            MentorDashboard dashboard,
            AppDependencies dependencies,
          ) => ListView(
            padding: const EdgeInsets.fromLTRB(
              20,
              AppSpacing.s16,
              20,
              AppSpacing.s24,
            ),
            children: <Widget>[
              MentorDashboardSection(
                data: dashboard,
                onGoToQuestions: () => TabNavigator.go(AppTab.questionRoom),
              ),
            ],
          ),
      notFoundMessage: '정산 요약을 불러올 수 없어요.',
      errorMessage: '정산 요약을 불러오지 못했어요.',
    );
  }
}

class _NotificationsTabIcon extends StatelessWidget {
  const _NotificationsTabIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: AppScope.of(context).notificationBadge.count,
      builder: (BuildContext context, int? count, Widget? _) {
        final String? label = notificationBadgeLabel(count);
        return Badge(
          isLabelVisible: label != null,
          label: label == null ? null : Text(label),
          child: Icon(icon),
        );
      },
    );
  }
}

class _ProfileCircleButton extends StatelessWidget {
  const _ProfileCircleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
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
            color: scheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person_rounded, size: 22, color: scheme.primary),
        ),
      ),
    );
  }
}
