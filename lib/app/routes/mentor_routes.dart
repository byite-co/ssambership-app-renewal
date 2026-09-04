import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/mentors/data/mentor_favorites_repository.dart';
import '../../features/mentors/data/mentor_models.dart';
import '../../features/mentors/ui/mentor_detail_screen.dart';
import '../app_route_paths.dart';
import '../app_scope.dart';
import '../async_route_loader.dart';

List<RouteBase> buildMentorRoutes() => <RouteBase>[
      GoRoute(
        path: '${AppRoutePaths.mentors}/:mentorId',
        builder: (context, state) => MentorDetailRoutePage(
          mentorId: state.pathParameters['mentorId']!,
        ),
      ),
    ];

/// ID-addressed mentor detail destination shared with non-production test
/// navigation fallbacks.
class MentorDetailRoutePage extends StatelessWidget {
  const MentorDetailRoutePage({super.key, required this.mentorId});

  final String mentorId;

  @override
  Widget build(BuildContext context) {
    return AsyncRouteLoader<_MentorDetailRouteData>(
      load: (dependencies) => _loadMentorDetail(dependencies, mentorId),
      builder: (context, data, dependencies) => MentorDetailScreen(
        item: data.item,
        initialFavorited: data.initialFavorited,
      ),
      notFoundMessage: '멘토를 찾을 수 없어요.',
      errorMessage: '멘토 정보를 불러오지 못했어요.',
    );
  }
}

Future<_MentorDetailRouteData?> _loadMentorDetail(
  AppDependencies dependencies,
  String mentorId,
) async {
  final MentorListItem? item =
      await dependencies.mentorDirectory.fetchListItemById(mentorId);
  if (item == null) return null;

  final MentorFavoritesLoad favorites =
      await dependencies.mentorFavorites.loadMyFavoriteMentorIds();
  return _MentorDetailRouteData(
    item: item,
    initialFavorited:
        favorites is MentorFavoritesLoaded && favorites.ids.contains(mentorId),
  );
}

class _MentorDetailRouteData {
  const _MentorDetailRouteData({
    required this.item,
    required this.initialFavorited,
  });

  final MentorListItem item;
  final bool initialFavorited;
}
