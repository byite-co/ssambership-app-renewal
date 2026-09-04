import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart' show AppRole;
import '../../features/question_room/data/models/room.dart';
import '../../features/question_room/ui/connection_notes_screen.dart';
import '../../features/question_room/ui/new_question_screen.dart';
import '../app_route_paths.dart';
import '../app_scope.dart';
import '../async_route_loader.dart';

/// Question-room detail routes are added one destination at a time.
List<RouteBase> buildQuestionRoomRoutes() => <RouteBase>[
      GoRoute(
        path: '${AppRoutePaths.rooms}/:roomId/threads/new',
        builder: (context, state) {
          final String roomId = state.pathParameters['roomId']!;
          return AsyncRouteLoader<Room>(
            load: (dependencies) =>
                dependencies.questionRoomRead.roomById(roomId),
            builder: (context, room, dependencies) => NewQuestionScreen(
              room: room,
              readRepository: dependencies.questionRoomRead,
              writeRepository: dependencies.questionRoomWrite,
            ),
          );
        },
      ),
      GoRoute(
        path: '${AppRoutePaths.rooms}/:roomId/notes',
        builder: (context, state) {
          final String roomId = state.pathParameters['roomId']!;
          return AsyncRouteLoader<_ConnectionNotesRouteData>(
            load: (dependencies) =>
                _loadConnectionNotesRoute(dependencies, roomId),
            builder: (context, data, dependencies) => ConnectionNotesScreen(
              room: data.room,
              mentorName: data.otherName,
            ),
          );
        },
      ),
    ];

Future<_ConnectionNotesRouteData?> _loadConnectionNotesRoute(
  AppDependencies dependencies,
  String roomId,
) async {
  final Room? room = await dependencies.questionRoomRead.roomById(roomId);
  if (room == null) return null;

  final String otherName;
  if (dependencies.auth.currentRole == AppRole.mentor) {
    otherName =
        (await dependencies.studentLookup.fetch(room.studentId))?.displayName ??
            '학생';
  } else {
    otherName =
        (await dependencies.mentorLookup.fetch(room.mentorId))?.displayName ??
            '멘토';
  }
  return _ConnectionNotesRouteData(room: room, otherName: otherName);
}

class _ConnectionNotesRouteData {
  const _ConnectionNotesRouteData({
    required this.room,
    required this.otherName,
  });

  final Room room;
  final String otherName;
}
