import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_service.dart' show AppRole;
import '../../core/entitlement/subscription_summary.dart';
import '../../features/mentors/ui/free_question_compose_screen.dart';
import '../../features/question_room/data/models/question_attachment.dart';
import '../../features/question_room/data/models/question_thread.dart';
import '../../features/question_room/data/models/room.dart';
import '../../features/question_room/ui/attachment_viewer_screen.dart';
import '../../features/question_room/ui/chat_screen.dart';
import '../../features/question_room/ui/connection_notes_screen.dart';
import '../../features/question_room/ui/mentor/mentor_answer_screen.dart';
import '../../features/question_room/ui/mentor/mentor_question_list_screen.dart';
import '../../features/question_room/ui/mentor/student_room_home_screen.dart';
import '../../features/question_room/ui/mentor_room_home_screen.dart';
import '../../features/question_room/ui/new_question_screen.dart';
import '../../features/question_room/ui/question_list_screen.dart';
import '../app_route_paths.dart';
import '../app_scope.dart';
import '../async_route_loader.dart';

/// Question-room detail routes are added one destination at a time.
List<RouteBase> buildQuestionRoomRoutes() => <RouteBase>[
      GoRoute(
        path: '${AppRoutePaths.rooms}/:roomId/free-question',
        builder: (context, state) {
          final String roomId = state.pathParameters['roomId']!;
          return AsyncRouteLoader<_FreeQuestionRouteData>(
            key: ValueKey<String>(roomId),
            load: (dependencies) =>
                _loadFreeQuestionRoute(dependencies, roomId),
            builder: (context, data, dependencies) => FreeQuestionComposeScreen(
              roomId: data.room.id,
              mentorName: data.mentorName,
              port: dependencies.freeQuestionEntry,
            ),
            notFoundMessage: '질문방을 찾을 수 없어요.',
            errorMessage: '무료 질문 정보를 불러오지 못했어요.',
          );
        },
      ),
      GoRoute(
        path: '${AppRoutePaths.rooms}/:roomId/threads/new',
        builder: (context, state) {
          final String roomId = state.pathParameters['roomId']!;
          return AsyncRouteLoader<Room>(
            key: ValueKey<String>(roomId),
            load: (dependencies) => _loadNewQuestionRoute(
              dependencies,
              roomId,
            ),
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
            key: ValueKey<String>(roomId),
            load: (dependencies) =>
                _loadConnectionNotesRoute(dependencies, roomId),
            builder: (context, data, dependencies) => ConnectionNotesScreen(
              room: data.room,
              mentorName: data.otherName,
            ),
          );
        },
      ),
      GoRoute(
        path: '${AppRoutePaths.rooms}/:roomId/threads',
        builder: (context, state) {
          final String roomId = state.pathParameters['roomId']!;
          return AsyncRouteLoader<_ThreadListRouteData>(
            key: ValueKey<String>(roomId),
            load: (dependencies) => _loadThreadListRoute(dependencies, roomId),
            builder: (context, data, dependencies) {
              if (data.role == AppRole.mentor) {
                return MentorQuestionListScreen(
                  room: data.room,
                  studentName: data.otherName,
                );
              }
              return QuestionListScreen(
                room: data.room,
                mentorName: data.otherName,
                sub: data.subscription,
                readRepository: dependencies.questionRoomRead,
                writeRepository: dependencies.questionRoomWrite,
              );
            },
          );
        },
      ),
      GoRoute(
        path:
            '${AppRoutePaths.rooms}/:roomId/threads/:threadId/attachments/:attachmentId',
        builder: (context, state) {
          final String roomId = state.pathParameters['roomId']!;
          final String threadId = state.pathParameters['threadId']!;
          final String attachmentId = state.pathParameters['attachmentId']!;
          return AsyncRouteLoader<_AttachmentRouteData>(
            key: ValueKey<String>('$roomId/$threadId/$attachmentId'),
            load: (dependencies) => _loadAttachmentRoute(
                dependencies, roomId, threadId, attachmentId),
            builder: (context, data, dependencies) => AttachmentViewerScreen(
              attachment: data.attachment,
              roomId: data.room.id,
              threadId: data.thread.id,
              resolver: dependencies.attachmentUrlResolver,
            ),
            notFoundMessage: '첨부 이미지를 찾을 수 없어요.',
            errorMessage: '첨부 이미지를 불러오지 못했어요.',
          );
        },
      ),
      GoRoute(
        path: '${AppRoutePaths.rooms}/:roomId/threads/:threadId',
        builder: (context, state) {
          final String roomId = state.pathParameters['roomId']!;
          final String threadId = state.pathParameters['threadId']!;
          return AsyncRouteLoader<_ThreadRouteData>(
            key: ValueKey<String>('$roomId/$threadId'),
            load: (dependencies) =>
                _loadThreadRoute(dependencies, roomId, threadId),
            builder: (context, data, dependencies) {
              if (data.role == AppRole.mentor) {
                return MentorAnswerScreen(
                  thread: data.thread,
                  studentName: data.otherName,
                  room: data.room,
                  uploader: dependencies.attachmentUploader,
                  safety: dependencies.roomSafety,
                  currentUserIdOverride: dependencies.auth.currentUserId,
                  readRepository: dependencies.questionRoomRead,
                );
              }
              return ChatScreen(
                thread: data.thread,
                mentorName: data.otherName,
                room: data.room,
                uploader: dependencies.attachmentUploader,
                safety: dependencies.roomSafety,
                currentUserIdOverride: dependencies.auth.currentUserId,
                readRepository: dependencies.questionRoomRead,
              );
            },
          );
        },
      ),
      GoRoute(
        path: '${AppRoutePaths.rooms}/:roomId',
        builder: (context, state) {
          final String roomId = state.pathParameters['roomId']!;
          return AsyncRouteLoader<_RoomHomeRouteData>(
            key: ValueKey<String>(roomId),
            load: (dependencies) => _loadRoomHomeRoute(dependencies, roomId),
            builder: (context, data, dependencies) {
              if (data.role == AppRole.mentor) {
                return StudentRoomHomeScreen(
                  room: data.room,
                  studentName: data.otherName,
                );
              }
              return MentorRoomHomeScreen(
                room: data.room,
                mentorName: data.otherName,
                sub: data.subscription,
              );
            },
          );
        },
      ),
    ];

Future<Room?> _loadNewQuestionRoute(
  AppDependencies dependencies,
  String roomId,
) {
  if (dependencies.auth.currentRole != AppRole.student) {
    return Future<Room?>.value();
  }
  return dependencies.questionRoomRead.roomById(roomId);
}

Future<_FreeQuestionRouteData?> _loadFreeQuestionRoute(
  AppDependencies dependencies,
  String roomId,
) async {
  if (dependencies.auth.currentRole != AppRole.student) return null;
  final Room? room = await dependencies.questionRoomRead.roomById(roomId);
  if (room == null) return null;

  final String mentorName =
      (await dependencies.mentorLookup.fetch(room.mentorId))?.displayName ??
          '멘토';
  return _FreeQuestionRouteData(room: room, mentorName: mentorName);
}

class _FreeQuestionRouteData {
  const _FreeQuestionRouteData({
    required this.room,
    required this.mentorName,
  });

  final Room room;
  final String mentorName;
}

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

Future<_ThreadListRouteData?> _loadThreadListRoute(
  AppDependencies dependencies,
  String roomId,
) async {
  final Room? room = await dependencies.questionRoomRead.roomById(roomId);
  if (room == null) return null;

  final AppRole role = dependencies.auth.currentRole;
  if (role == AppRole.mentor) {
    final String studentName =
        (await dependencies.studentLookup.fetch(room.studentId))?.displayName ??
            '학생';
    return _ThreadListRouteData(
      room: room,
      role: role,
      otherName: studentName,
    );
  }

  final String mentorName =
      (await dependencies.mentorLookup.fetch(room.mentorId))?.displayName ??
          '멘토';
  final Map<String, SubscriptionSummary> subscriptions =
      await dependencies.subscriptions.fetchForStudent(room.studentId);
  return _ThreadListRouteData(
    room: room,
    role: role,
    otherName: mentorName,
    subscription: subscriptions[room.mentorId],
  );
}

class _ThreadListRouteData {
  const _ThreadListRouteData({
    required this.room,
    required this.role,
    required this.otherName,
    this.subscription,
  });

  final Room room;
  final AppRole role;
  final String otherName;
  final SubscriptionSummary? subscription;
}

Future<_RoomHomeRouteData?> _loadRoomHomeRoute(
  AppDependencies dependencies,
  String roomId,
) async {
  final Room? room = await dependencies.questionRoomRead.roomById(roomId);
  if (room == null) return null;

  final AppRole role = dependencies.auth.currentRole;
  if (role == AppRole.mentor) {
    final String studentName =
        (await dependencies.studentLookup.fetch(room.studentId))?.displayName ??
            '학생';
    return _RoomHomeRouteData(
      room: room,
      role: role,
      otherName: studentName,
    );
  }

  final String mentorName =
      (await dependencies.mentorLookup.fetch(room.mentorId))?.displayName ??
          '멘토';
  final Map<String, SubscriptionSummary> subscriptions =
      await dependencies.subscriptions.fetchForStudent(room.studentId);
  return _RoomHomeRouteData(
    room: room,
    role: role,
    otherName: mentorName,
    subscription: subscriptions[room.mentorId],
  );
}

class _RoomHomeRouteData {
  const _RoomHomeRouteData({
    required this.room,
    required this.role,
    required this.otherName,
    this.subscription,
  });

  final Room room;
  final AppRole role;
  final String otherName;
  final SubscriptionSummary? subscription;
}

Future<_ThreadRouteData?> _loadThreadRoute(
  AppDependencies dependencies,
  String roomId,
  String threadId,
) async {
  final Room? room = await dependencies.questionRoomRead.roomById(roomId);
  final QuestionThread? thread =
      await dependencies.questionRoomRead.threadById(threadId);
  if (room == null || thread == null || thread.roomId != room.id) return null;

  final AppRole role = dependencies.auth.currentRole;
  final String otherName;
  if (role == AppRole.mentor) {
    otherName =
        (await dependencies.studentLookup.fetch(room.studentId))?.displayName ??
            '학생';
  } else {
    otherName =
        (await dependencies.mentorLookup.fetch(room.mentorId))?.displayName ??
            '멘토';
  }
  return _ThreadRouteData(
    room: room,
    thread: thread,
    role: role,
    otherName: otherName,
  );
}

class _ThreadRouteData {
  const _ThreadRouteData({
    required this.room,
    required this.thread,
    required this.role,
    required this.otherName,
  });

  final Room room;
  final QuestionThread thread;
  final AppRole role;
  final String otherName;
}

Future<_AttachmentRouteData?> _loadAttachmentRoute(
  AppDependencies dependencies,
  String roomId,
  String threadId,
  String attachmentId,
) async {
  final List<Object?> rows = await Future.wait<Object?>(<Future<Object?>>[
    dependencies.questionRoomRead.roomById(roomId),
    dependencies.questionRoomRead.threadById(threadId),
    dependencies.questionRoomRead.attachments(threadId),
  ]);
  final Room? room = rows[0] as Room?;
  final QuestionThread? thread = rows[1] as QuestionThread?;
  final List<QuestionAttachment> attachments =
      rows[2]! as List<QuestionAttachment>;
  QuestionAttachment? attachment;
  for (final QuestionAttachment candidate in attachments) {
    if (candidate.id == attachmentId) {
      attachment = candidate;
      break;
    }
  }
  if (room == null ||
      room.id != roomId ||
      thread == null ||
      thread.id != threadId ||
      thread.roomId != room.id ||
      attachment == null ||
      attachment.id != attachmentId ||
      attachment.threadId != thread.id) {
    return null;
  }
  return _AttachmentRouteData(
    room: room,
    thread: thread,
    attachment: attachment,
  );
}

class _AttachmentRouteData {
  const _AttachmentRouteData({
    required this.room,
    required this.thread,
    required this.attachment,
  });

  final Room room;
  final QuestionThread thread;
  final QuestionAttachment attachment;
}
