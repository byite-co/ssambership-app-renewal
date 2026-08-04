import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_service.dart';
import '../core/refresh/data_refresh_bus.dart';
import '../features/community/community_screen.dart';
import '../features/individual_question/individual_question_tab_screen.dart';
import '../features/mentors/mentors_screen.dart';
import '../features/mypage/data/mypage_models.dart';
import '../features/mypage/mypage_screen.dart';
import '../features/notifications/data/notification_badge_controller.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/question_room/question_room_screen.dart';
import '../shared/constants/app_constants.dart';
import '../shared/widgets/withdrawal_pending_banner.dart';
import 'app_tabs.dart';
import 'entry_guard.dart';

/// 하단 탭 5개 셸(질문방·커뮤니티·멘토찾기·알림·개별질문).
///
/// 마이페이지는 하단 탭이 아니라 AppBar 우측 상단의 '원형 프로필' 버튼으로
/// 진입한다(push). 개별질문이 그 자리를 이어받아 다른 기능과 동일 위상이 된다.
///
/// 게스트(둘러보기)는 커뮤니티·멘토찾기만 접근 가능.
/// 질문방·알림·개별질문·마이페이지를 누르면 "로그인이 필요해요" 안내와 함께
/// 로그인 화면으로 보낸다.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.myPageLoaderOverride});

  /// 테스트용 마이페이지 데이터 주입(loaderOverride 패턴) — 실사용은 null.
  final Future<MyPageData> Function()? myPageLoaderOverride;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index;

  static const List<Widget> _pages = <Widget>[
    QuestionRoomScreen(),
    CommunityScreen(),
    MentorsScreen(),
    NotificationsScreen(),
    IndividualQuestionTabScreen(),
  ];

  // 아이콘 통일: Material Symbols rounded 한 세트(하단 탭·검색·액션 혼용 제거).
  static const List<IconData> _icons = <IconData>[
    Icons.forum_rounded,
    Icons.groups_rounded,
    Icons.search_rounded,
    Icons.notifications_rounded,
    Icons.question_answer_rounded,
  ];

  @override
  void initState() {
    super.initState();
    // 게스트는 접근 가능한 탭(멘토 찾기=2)에서 시작.
    _index = AuthService.instance.isGuest ? 2 : 0;
    // 알림 딥링크 등 앱 내 탭 전환 요청 수신.
    TabNavigator.request.addListener(_onTabRequest);
    // 로그인 사용자 — 알림 배지 서버 개수 1회 조회(이후는 실시간·화면이 갱신).
    if (!AuthService.instance.isGuest) {
      NotificationBadgeController.instance.refresh();
    }
  }

  @override
  void dispose() {
    TabNavigator.request.removeListener(_onTabRequest);
    // 로그아웃/계정 전환으로 셸이 내려가면 이전 사용자 배지 개수를 폐기한다
    // (다음 로그인 셸이 서버에서 새로 조회 — 교차 사용자 잔상 0).
    NotificationBadgeController.instance.clear();
    super.dispose();
  }

  /// 탭 전환 요청 처리(딥링크). 처리 후 -1 로 되돌려 같은 탭 재요청도 감지.
  /// AppTab.myPage(가상 목적지)는 탭 전환이 아니라 마이페이지 push 로 처리.
  void _onTabRequest() {
    final int i = TabNavigator.request.value;
    if (i < 0) return;
    if (i == AppTab.myPage) {
      _openMyPage();
    } else {
      _onSelect(i);
    }
    TabNavigator.request.value = -1;
  }

  void _onSelect(int i) {
    if (AuthService.instance.isGuest && !EntryGuard.isTabAllowedForGuest(i)) {
      context.go('${EntryGuard.login}?notice=login_required');
      return;
    }
    // 알림 탭 선택(재선택 포함) — 살아 있는 알림 화면에 재조회 신호.
    if (i == AppTab.notifications) DataRefreshBus.bumpNotifications();
    setState(() => _index = i);
  }

  /// 우측 상단 프로필(원형) → 마이페이지 push. 게스트는 로그인 안내로 보낸다.
  ///
  /// 마이페이지 안의 '알림'·'받은 질문 보기' 등 탭 이동 액션은 **pop 결과(탭 index)**
  /// 로 돌아온다 — push 된 마이페이지가 화면을 덮은 채 숨은 탭 index 만 바뀌던
  /// 무반응 구조를 제거한다(route 를 닫고 나서 실제 보이는 탭을 전환).
  Future<void> _openMyPage() async {
    if (AuthService.instance.isGuest) {
      context.go('${EntryGuard.login}?notice=login_required');
      return;
    }
    final int? tab = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) =>
            _MyPagePage(loaderOverride: widget.myPageLoaderOverride),
      ),
    );
    if (!mounted || tab == null) return;
    _onSelect(tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppConstants.bottomTabLabels[_index]),
        actions: <Widget>[
          // 마이페이지 진입점: 원형 도형 속 프로필(person) 아이콘.
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ProfileCircleButton(onTap: _openMyPage),
          ),
        ],
      ),
      // §5-1: 탈퇴 예약 상시 배너 — 어느 탭에 있어도 보이도록 셸 레벨에 둔다.
      // 노출·취소버튼 판정은 전부 서버 정본(DeletionNoticeController).
      body: Column(
        children: <Widget>[
          const WithdrawalPendingBanner(),
          Expanded(child: IndexedStack(index: _index, children: _pages)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onSelect,
        destinations: <NavigationDestination>[
          for (int i = 0; i < _pages.length; i++)
            NavigationDestination(
              // 알림 탭만 서버 미읽음 개수 배지(0/미확인이면 숨김, 100+ → '99+').
              icon: i == AppTab.notifications
                  ? _NotificationsTabIcon(icon: _icons[i])
                  : Icon(_icons[i]),
              label: AppConstants.bottomTabLabels[i],
            ),
        ],
      ),
    );
  }
}

/// 알림 탭 아이콘 + 서버 미읽음 배지.
///
/// ★ 배지의 유일한 소스는 서버 개수([NotificationBadgeController] —
///   notification_unread_count_self)다. 로컬 목록으로 개수를 계산하지 않는다.
///   null(미확인)·0 → 배지 숨김, 100 이상 → '99+'.
class _NotificationsTabIcon extends StatelessWidget {
  const _NotificationsTabIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: NotificationBadgeController.instance.count,
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

/// 원형 배경 + 프로필 실루엣 아이콘(우측 상단 마이페이지 진입 버튼).
/// ★ 사진 placeholder 를 쓰지 않고 중립 원형 + person 아이콘으로 통일
///   (InitialAvatar 규약과 동일한 '깨진 이미지 금지' 원칙).
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

/// 마이페이지 push 라우트 래퍼.
/// MyPageScreen 은 본문만 그리므로(자체 Scaffold 없음) 여기서 AppBar 를 씌운다.
/// 탭 이동 액션(알림·받은 질문 보기·질문하러 가기)은 이 route 를 **pop 하면서
/// 목적지 탭 index 를 반환**한다 — HomeShell 이 받아 실제 보이는 탭을 전환한다.
class _MyPagePage extends StatelessWidget {
  const _MyPagePage({this.loaderOverride});

  final Future<MyPageData> Function()? loaderOverride;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.myPageTitle)),
      body: MyPageScreen(
        loaderOverride: loaderOverride,
        onOpenQuestionsTab: () =>
            Navigator.of(context).pop(AppTab.questionRoom),
        onOpenNotifications: () =>
            Navigator.of(context).pop(AppTab.notifications),
      ),
    );
  }
}
