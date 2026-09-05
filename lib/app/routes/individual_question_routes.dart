import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/individual_question/ui/iq_create_screen.dart';
import '../../features/individual_question/ui/iq_detail_screen.dart';
import '../app_route_completion.dart';
import '../app_route_paths.dart';

List<RouteBase> buildIndividualQuestionRoutes() => <RouteBase>[
      // A-4a #11: 네이티브 등록(`/iq/new`). 질문 id 파라미터 라우트보다 먼저
      // 등록해 'new' 가 질문 id 로 잡히지 않게 한다. 학생 전용 가드는 AppRouter._redirect.
      GoRoute(
        path: AppRoutePaths.newIndividualQuestion,
        builder: (context, state) {
          final String? mentorId = state.uri.queryParameters['mentor'];
          final String? mentorName = state.uri.queryParameters['name'];
          return AppRouteCompletionBoundary(
            fallbackLocation: AppRoutePaths.individualQuestions,
            child: IqCreateScreen(
              key: ValueKey<String>('iq-create:${mentorId ?? 'open'}'),
              mentorId: (mentorId == null || mentorId.isEmpty) ? null : mentorId,
              mentorName:
                  (mentorName == null || mentorName.isEmpty) ? null : mentorName,
            ),
          );
        },
      ),
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
