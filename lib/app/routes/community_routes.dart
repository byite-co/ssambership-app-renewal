import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/community/data/community_models.dart';
import '../../features/community/ui/board/board_detail_screen.dart';
import '../../features/community/ui/board/board_write_screen.dart';
import '../../features/community/ui/shortform/shortform_compose_screen.dart';
import '../../features/community/ui/shortform/shortform_detail_screen.dart';
import '../app_route_paths.dart';
import '../app_scope.dart';
import '../async_route_loader.dart';

/// Community detail routes are added one destination at a time during A-3.
List<RouteBase> buildCommunityRoutes() => <RouteBase>[
      GoRoute(
        path: AppRoutePaths.newBoardPost,
        builder: (context, state) =>
            BoardWriteScreen(write: AppScope.of(context).communityWrite),
      ),
      GoRoute(
        path: '${AppRoutePaths.boardPosts}/:postId/edit',
        builder: (context, state) => BoardEditRoutePage(
          postId: state.pathParameters['postId']!,
        ),
      ),
      GoRoute(
        path: AppRoutePaths.newShortform,
        builder: (context, state) => ShortformComposeScreen(
          supabaseClient: AppScope.of(context).supabaseClient,
        ),
      ),
      GoRoute(
        path: '${AppRoutePaths.boardPosts}/:postId',
        builder: (context, state) {
          final String postId = state.pathParameters['postId']!;
          return AsyncRouteLoader<BoardPost>(
            key: ValueKey<String>('board-detail/$postId'),
            load: (dependencies) =>
                dependencies.communityRead.boardPostById(postId),
            builder: (context, post, dependencies) => BoardDetailScreen(
              post: post,
              read: dependencies.communityRead,
              write: dependencies.communityWrite,
            ),
            notFoundMessage: '게시글을 찾을 수 없어요.',
            errorMessage: '게시글을 불러오지 못했어요.',
          );
        },
      ),
      GoRoute(
        path: '${AppRoutePaths.shortforms}/:shortformId',
        builder: (context, state) {
          final String shortformId = state.pathParameters['shortformId']!;
          return AsyncRouteLoader<ShortformPost>(
            key: ValueKey<String>(shortformId),
            load: (dependencies) =>
                dependencies.communityRead.shortformById(shortformId),
            builder: (context, post, dependencies) => ShortformDetailScreen(
              post: post,
              read: dependencies.communityRead,
              write: dependencies.communityWrite,
            ),
            notFoundMessage: '숏폼을 찾을 수 없어요.',
            errorMessage: '숏폼을 불러오지 못했어요.',
          );
        },
      ),
    ];

/// Re-fetches an edit target and proves that it still belongs to the current
/// user before the write surface is built.
///
/// The update RPC remains the security authority. This route boundary prevents
/// a copied or stale edit URL from exposing another user's editor or starting
/// image uploads for that post.
class BoardEditRoutePage extends StatelessWidget {
  const BoardEditRoutePage({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context) => AsyncRouteLoader<BoardPost>(
        key: ValueKey<String>(
          'board-edit/$postId/'
          '${AppScope.of(context).auth.currentUserId ?? 'signed-out'}',
        ),
        load: (dependencies) => _loadOwnedBoardPost(dependencies, postId),
        builder: (context, post, dependencies) => BoardWriteScreen(
            write: dependencies.communityWrite, editing: post),
        // Missing, RLS-hidden, and not-owned targets intentionally converge on
        // the same neutral response so ownership is not disclosed.
        notFoundMessage: '게시글을 찾을 수 없어요.',
        errorMessage: '게시글을 불러오지 못했어요.',
      );
}

Future<BoardPost?> _loadOwnedBoardPost(
  AppDependencies dependencies,
  String postId,
) async {
  final String? userId = dependencies.auth.currentUserId;
  if (userId == null) return null;

  final BoardPost? post =
      await dependencies.communityRead.boardPostById(postId);
  if (post == null || post.id != postId || post.authorId != userId) {
    return null;
  }
  return post;
}
