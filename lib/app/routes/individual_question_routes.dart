import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/individual_question/ui/iq_detail_screen.dart';
import '../app_route_completion.dart';
import '../app_route_paths.dart';

List<RouteBase> buildIndividualQuestionRoutes() => <RouteBase>[
      GoRoute(
        path: '${AppRoutePaths.individualQuestions}/:questionId',
        builder: (context, state) {
          final String questionId = state.pathParameters['questionId']!;
          return AppRouteCompletionBoundary(
            fallbackLocation: AppRoutePaths.individualQuestions,
            child: IqDetailScreen(
              key: ValueKey<String>('iq-detail:$questionId'),
              questionId: questionId,
            ),
          );
        },
      ),
    ];
