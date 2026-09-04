import 'package:go_router/go_router.dart';

import '../../features/question_room/data/models/room.dart';
import '../../features/question_room/ui/new_question_screen.dart';
import '../app_route_paths.dart';
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
    ];
