import 'package:go_router/go_router.dart';

import '../core/auth/auth_service.dart' show AccessState, AppRole;
import '../features/auth/blocked_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/community/community_screen.dart';
import '../features/dev/dev_flags.dart';
import '../features/dev/s3_data_inspector.dart';
import '../features/dev/widget_gallery.dart';
import '../features/individual_question/individual_question_tab_screen.dart';
import '../features/mentors/mentors_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/question_room/question_room_screen.dart';
import 'app_navigation.dart';
import 'app_route_paths.dart';
import 'app_scope.dart';
import 'entry_guard.dart';
import 'home_shell.dart';
import 'routes/community_routes.dart';
import 'routes/individual_question_routes.dart';
import 'routes/mentor_routes.dart';
import 'routes/mypage_routes.dart';
import 'routes/question_room_routes.dart';

/// 라우팅: 스플래시 → (로그인 | 차단 | 홈). 진입 분기는 EntryGuard 가 결정한다.
/// AuthService(ChangeNotifier)를 refreshListenable 로 두어 상태 변화 시 재평가.
class AppRouter {
  AppRouter._();

  /// Creates the single router owned by the root app lifecycle.
  static GoRouter create(AppDependencies dependencies) {
    final GoRouter router = GoRouter(
      initialLocation: EntryGuard.splash,
      refreshListenable: dependencies.auth,
      redirect: (context, state) =>
          _redirect(dependencies, state.matchedLocation),
      routes: <RouteBase>[
        // Legacy entry aliases. The top-level redirect resolves these to the
        // current role's canonical first tab before a page is built.
        GoRoute(path: AppRoutePaths.root, redirect: (_, __) => null),
        GoRoute(
          path: EntryGuard.splash,
          builder: (context, state) => const SplashScreen(),
        ),
        GoRoute(
          path: EntryGuard.login,
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(path: EntryGuard.home, redirect: (_, __) => null),
        GoRoute(
          path: EntryGuard.blocked,
          builder: (context, state) => const BlockedScreen(),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => HomeShell(
            navigationShell: navigationShell,
            location: state.uri.path,
          ),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: AppRoutePaths.rooms,
                  builder: (context, state) => const HomeTabBranch(
                    branchIndex: 0,
                    child: QuestionRoomScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: AppRoutePaths.individualQuestions,
                  builder: (context, state) => const HomeTabBranch(
                    branchIndex: 1,
                    child: IndividualQuestionTabScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              initialLocation: AppRoutePaths.mentors,
              routes: <RouteBase>[
                // One navigator owns both role variants. `/mentors` remains a
                // valid mentor deep URL even though their visible tab is 정산.
                GoRoute(
                  path: AppRoutePaths.mentors,
                  builder: (context, state) => const HomeTabBranch(
                    branchIndex: 2,
                    child: MentorsScreen(),
                  ),
                ),
                GoRoute(
                  path: AppRoutePaths.settlements,
                  builder: (context, state) => const HomeTabBranch(
                    branchIndex: 2,
                    child: MentorSettlementsTabBody(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: AppRoutePaths.community,
                  builder: (context, state) => const HomeTabBranch(
                    branchIndex: 3,
                    child: CommunityScreen(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <RouteBase>[
                GoRoute(
                  path: AppRoutePaths.notifications,
                  builder: (context, state) => const HomeTabBranch(
                    branchIndex: 4,
                    child: NotificationsScreen(),
                  ),
                ),
              ],
            ),
          ],
        ),
        ...buildQuestionRoomRoutes(),
        ...buildIndividualQuestionRoutes(),
        ...buildMentorRoutes(),
        ...buildCommunityRoutes(),
        ...buildMyPageRoutes(),
        // ★ 개발 전용 — 출시(release) 빌드에서는 등록되지 않는다(kDevToolsEnabled=false).
        if (kDevToolsEnabled)
          GoRoute(
            path: EntryGuard.devGallery,
            builder: (context, state) => const WidgetGallery(),
          ),
        if (kDevToolsEnabled)
          GoRoute(
            path: EntryGuard.devS3,
            builder: (context, state) => const S3DataInspector(),
          ),
      ],
    );
    AppNavigation.markProductionRouter(router);
    return router;
  }

  static String? _redirect(AppDependencies dependencies, String location) {
    final AccessState access = dependencies.routingAccess;
    final String? guarded = EntryGuard.redirect(
      access: access,
      location: location,
    );
    final String destination = guarded ?? location;

    if (destination == AppRoutePaths.root ||
        destination == AppRoutePaths.home) {
      if (access == AccessState.guest) return AppRoutePaths.mentors;
      if (access == AccessState.full) return AppRoutePaths.rooms;
    }

    // 정산은 멘토의 canonical tab이다. 학생이 URL을 직접 입력해도 멘토
    // 데이터 표면을 열지 않고 자신의 첫 탭으로 수렴한다.
    if (access == AccessState.full &&
        dependencies.auth.currentRole != AppRole.mentor &&
        destination == AppRoutePaths.settlements) {
      return AppRoutePaths.rooms;
    }
    return guarded;
  }
}
