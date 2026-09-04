import 'package:go_router/go_router.dart';

import '../../features/individual_question/ui/iq_detail_screen.dart';
import '../app_route_paths.dart';

List<RouteBase> buildIndividualQuestionRoutes() => <RouteBase>[
  GoRoute(
    path: '${AppRoutePaths.individualQuestions}/:questionId',
    builder: (context, state) =>
        IqDetailScreen(questionId: state.pathParameters['questionId']!),
  ),
];
