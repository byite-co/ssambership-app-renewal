import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart' show AppRole;
import '../../features/community/ui/blocks/blocked_users_screen.dart';
import '../../features/mentor_console/ui/mentor_settlement_screen.dart';
import '../../features/mypage/data/mypage_models.dart';
import '../../features/mypage/mypage_screen.dart';
import '../../features/mypage/ui/account_delete_screen.dart';
import '../../features/mypage/ui/profile_edit_screen.dart';
import '../../shared/constants/app_constants.dart';
import '../app_navigation.dart';
import '../app_route_completion.dart';
import '../app_route_paths.dart';
import '../app_scope.dart';
import '../app_tabs.dart';
import '../async_route_loader.dart';

/// My-page routes are added one destination at a time during A-3.
List<RouteBase> buildMyPageRoutes() => <RouteBase>[
      GoRoute(
        path: AppRoutePaths.myPage,
        builder: (BuildContext context, GoRouterState state) =>
            const AppRouteCompletionBoundary(
          fallbackLocation: AppRoutePaths.rooms,
          child: MyPageRoutePage(),
        ),
      ),
      GoRoute(
        path: AppRoutePaths.accountDeletion,
        builder: (BuildContext context, GoRouterState state) {
          final AppDependencies dependencies = AppScope.of(context);
          return AppRouteCompletionBoundary(
            fallbackLocation: AppRoutePaths.myPage,
            child: AccountDeleteScreen(
              port: dependencies.accountDeletion,
              signOutOverride: dependencies.auth.signOut,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutePaths.profileEdit,
        builder: (BuildContext context, GoRouterState state) =>
            AppRouteCompletionBoundary(
          fallbackLocation: AppRoutePaths.myPage,
          child: AsyncRouteLoader<MyProfile>(
            load: (dependencies) async =>
                (await dependencies.myPage.load()).profile,
            builder: (context, profile, dependencies) => ProfileEditScreen(
              profile: profile,
              repository: dependencies.profileEdit,
            ),
            errorMessage: '프로필을 불러오지 못했어요.',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutePaths.blockedUsers,
        builder: (BuildContext context, GoRouterState state) =>
            AppRouteCompletionBoundary(
          fallbackLocation: AppRoutePaths.myPage,
          child: BlockedUsersScreen(
            repository: AppScope.of(context).userBlocks,
          ),
        ),
      ),
    ];

/// Route-level scaffold for [MyPageScreen].
///
/// Tab hand-offs close this pushed route with the destination URL so the
/// underlying home shell can navigate after the pop completes.
class MyPageRoutePage extends StatelessWidget {
  const MyPageRoutePage({super.key, this.loaderOverride});

  /// Existing focused widget tests can keep supplying deterministic data.
  final Future<MyPageData> Function()? loaderOverride;

  @override
  Widget build(BuildContext context) {
    final bool isMentor =
        AppScope.of(context).auth.currentRole == AppRole.mentor;
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.myPageTitle),
        actions: <Widget>[
          // A-4a: 멘토는 마이페이지에서도 정산 허브로 들어간다. 본문(MyPageScreen)은
          // 골든 고정이라 AppBar 액션으로만 진입점을 더한다.
          if (isMentor)
            IconButton(
              tooltip: MentorSettlementScreen.entryTooltip,
              icon: const Icon(Icons.receipt_long_rounded),
              onPressed: () => AppNavigation.push<void>(
                context,
                AppRoutePaths.settlementHistory,
                fallbackBuilder: (_) => const MentorSettlementScreen(),
              ),
            ),
        ],
      ),
      body: MyPageScreen(
        loaderOverride: loaderOverride,
        onOpenQuestionsTab: () => AppNavigation.complete<String>(
          context,
          result: AppTab.questionRoom,
          fallbackLocation: AppTab.questionRoom,
        ),
        onOpenNotifications: () => AppNavigation.complete<String>(
          context,
          result: AppTab.notifications,
          fallbackLocation: AppTab.notifications,
        ),
      ),
    );
  }
}
