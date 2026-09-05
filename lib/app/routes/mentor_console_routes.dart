import 'package:go_router/go_router.dart';

import '../../features/mentor_console/ui/mentor_plans_screen.dart';
import '../../features/mentor_console/ui/mentor_settlement_screen.dart';
import '../../features/mentor_console/ui/payout_account_screen.dart';
import '../../features/mentor_console/ui/settlement_lines_screen.dart';
import '../app_route_completion.dart';
import '../app_route_paths.dart';

/// A-4a 멘토 콘솔 라우트 — A-3 future slot(`/settlements/*`·`/profile/*`)을 채운다.
/// 역할 가드는 `AppRouter._redirect` 가 담당한다(멘토 전용, 학생은 첫 탭으로).
List<RouteBase> buildMentorConsoleRoutes() => <RouteBase>[
      GoRoute(
        path: AppRoutePaths.settlementHistory,
        builder: (context, state) => const AppRouteCompletionBoundary(
          fallbackLocation: AppRoutePaths.settlements,
          child: MentorSettlementScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutePaths.settlementLines,
        builder: (context, state) => const AppRouteCompletionBoundary(
          fallbackLocation: AppRoutePaths.settlementHistory,
          child: SettlementLinesScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutePaths.settlementAccount,
        builder: (context, state) => const AppRouteCompletionBoundary(
          fallbackLocation: AppRoutePaths.settlements,
          child: PayoutAccountScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutePaths.mentorPlans,
        builder: (context, state) => const AppRouteCompletionBoundary(
          fallbackLocation: AppRoutePaths.settlements,
          child: MentorPlansScreen(),
        ),
      ),
    ];
