import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/individual_question/ui/iq_create_screen.dart';
import '../../features/individual_question/ui/iq_detail_screen.dart';
import '../app_route_completion.dart';
import '../app_route_paths.dart';

/// 라우터 밖(위젯 테스트·소형 라우터)에서 개별질문 등록 화면을 만드는 폴백.
///
/// 계약(iq_create_boundary_test): `IqCreateScreen(` 생성자는 라우트·두 CTA 파일
/// 에만 둔다 — 다른 화면(주간 소진 §3-4 등)은 URL 로 push 하고 폴백은 여기서 받는다.
Widget buildIqCreateFallback({String? mentorId, String? mentorName}) =>
    IqCreateScreen(mentorId: mentorId, mentorName: mentorName);

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
