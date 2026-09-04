import '../core/auth/auth_service.dart';
import 'app_route_paths.dart';
import 'app_tabs.dart';

/// 진입 가드: AccessState → 가야 할 경로. router.redirect 에서 사용한다.
///
/// 분기 요약:
/// - loading  → /splash
/// - loggedOut→ /login (보호 경로 직접 접근 시에도 로그인으로)
/// - guest    → /mentors·/community + /login
/// - full     → 역할별 URL 탭과 상세 경로
/// - blocked  → /blocked (banned/suspended/상태불명/관리자)
class EntryGuard {
  EntryGuard._();

  static const String splash = AppRoutePaths.splash;
  static const String onboarding = AppRoutePaths.onboarding;
  static const String login = AppRoutePaths.login;
  static const String home = AppRoutePaths.home;
  static const String blocked = AppRoutePaths.blocked;
  static const String devGallery = AppRoutePaths.devGallery;
  static const String devS3 = AppRoutePaths.devS3;

  /// A-3 URL graph roots available to a fully authenticated app user.
  ///
  /// The routes are registered incrementally. Keeping the guard aware of the
  /// complete protected surface prevents a newly registered route from being
  /// collapsed back to legacy `/home` during that migration.
  static const List<String> _fullAccessRoots = <String>[
    AppRoutePaths.home,
    AppRoutePaths.rooms,
    AppRoutePaths.individualQuestions,
    AppRoutePaths.mentors,
    AppRoutePaths.settlements,
    AppRoutePaths.community,
    AppRoutePaths.notifications,
    AppRoutePaths.myPage,
    '/profile',
  ];

  /// 게스트가 접근 가능한 canonical 탭 경로. 역할별 순서와 무관하다.
  static const Set<String> guestAllowedTabs = <String>{
    AppTab.mentors,
    AppTab.community,
  };

  static bool isTabAllowedForGuest(String location) {
    final String path = Uri.tryParse(location)?.path ?? location;
    return guestAllowedTabs.contains(path);
  }

  /// redirect 결정. null = 현재 위치 유지.
  static String? redirect({
    required AccessState access,
    required String location,
  }) {
    // dev 라우트는 가드 제외(개발 빌드 한정으로만 등록됨).
    if (location.startsWith('/dev/')) return null;

    switch (access) {
      case AccessState.loading:
        return location == splash ? null : splash;
      case AccessState.loggedOut:
        return location == login || location == onboarding ? null : login;
      case AccessState.guest:
        // `/home`은 AppRouter가 공개 canonical 탭(`/mentors`)으로 바꾼다.
        if (location == home ||
            location == login ||
            location == onboarding ||
            _isGuestPublicLocation(location)) {
          return null;
        }
        return home;
      case AccessState.full:
        return _isFullAccessLocation(location) ? null : home;
      case AccessState.blocked:
        return location == blocked ? null : blocked;
    }
  }

  static bool _isFullAccessLocation(String location) {
    final String path = Uri.tryParse(location)?.path ?? location;
    for (final String root in _fullAccessRoots) {
      if (path == root || path.startsWith('$root/')) return true;
    }
    return false;
  }

  static bool _isGuestPublicLocation(String location) {
    final String path = Uri.tryParse(location)?.path ?? location;
    for (final String root in guestAllowedTabs) {
      if (path == root || path.startsWith('$root/')) return true;
    }
    return false;
  }
}
