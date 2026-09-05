import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ssambership_app/app/app_route_paths.dart';
import 'package:ssambership_app/app/app_scope.dart';
import 'package:ssambership_app/app/router.dart';
import 'package:ssambership_app/core/auth/account_status.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/individual_question/data/individual_question_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/individual_question/ui/iq_detail_screen.dart';
import 'package:ssambership_app/features/mentors/data/mentor_directory_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_favorites_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/question_room/data/mentor_lookup_repository.dart';
import 'package:ssambership_app/features/question_room/data/models/question_attachment.dart';
import 'package:ssambership_app/features/question_room/data/models/question_message.dart';
import 'package:ssambership_app/features/question_room/data/models/question_thread.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';
import 'package:ssambership_app/features/question_room/ui/chat_screen.dart';

import '../support/app_scope_test_harness.dart';

void main() {
  testWidgets(
    'production router reloads mentor detail when only mentorId changes',
    (WidgetTester tester) async {
      final _RecordingMentorDirectory directory =
          _RecordingMentorDirectory(const <String, MentorListItem>{
        'mentor-a': MentorListItem(id: 'mentor-a', nickname: '가 멘토'),
        'mentor-b': MentorListItem(id: 'mentor-b', nickname: '나 멘토'),
      });
      final AppDependencies dependencies = testAppDependencies(
        auth: TestAppAuth(
          role: AppRole.mentor,
          userId: 'mentor-user',
          account: AccountState.active,
        ),
        mentorDirectory: directory,
        mentorFavorites: const _EmptyMentorFavorites(),
      );
      final GoRouter router = await _pumpProductionRoute(
        tester,
        dependencies,
        AppRoutePaths.mentor('mentor-a'),
      );

      expect(directory.detailRequests, <String>['mentor-a']);
      expect(find.text('가 멘토'), findsWidgets);

      // Re-requesting the same logical entity must retain the cached future.
      router.go(AppRoutePaths.mentor('mentor-a'));
      await tester.pumpAndSettle();
      expect(directory.detailRequests, <String>['mentor-a']);

      router.go(AppRoutePaths.mentor('mentor-b'));
      await tester.pumpAndSettle();

      expect(directory.detailRequests, <String>['mentor-a', 'mentor-b']);
      expect(find.text('가 멘토'), findsNothing);
      expect(find.text('나 멘토'), findsWidgets);
    },
  );

  testWidgets(
    'production router reloads room thread when roomId and threadId change',
    (WidgetTester tester) async {
      final _RecordingQuestionRoomRead read = _RecordingQuestionRoomRead(
        rooms: <String, Room>{
          'room-a': _room('room-a', 'mentor-a'),
          'room-b': _room('room-b', 'mentor-b'),
        },
        threadRows: <String, QuestionThread>{
          'thread-a': _thread('thread-a', 'room-a'),
          'thread-b': _thread('thread-b', 'room-b'),
        },
      );
      final AppDependencies dependencies = testAppDependencies(
        auth: TestAppAuth(
          role: AppRole.student,
          userId: 'student-user',
          account: AccountState.active,
        ),
        questionRoomRead: read,
        mentorLookup: const _MentorLookup(),
      );
      final GoRouter router = await _pumpProductionRoute(
        tester,
        dependencies,
        AppRoutePaths.roomThread('room-a', 'thread-a'),
      );

      expect(read.roomRequests, <String>['room-a']);
      expect(read.threadRequests, <String>['thread-a']);
      expect(_visibleChat(tester).thread.id, 'thread-a');

      // An ordinary navigation notification for the same URI must not refetch.
      router.go(AppRoutePaths.roomThread('room-a', 'thread-a'));
      await tester.pumpAndSettle();
      expect(read.roomRequests, <String>['room-a']);
      expect(read.threadRequests, <String>['thread-a']);

      router.go(AppRoutePaths.roomThread('room-b', 'thread-b'));
      await tester.pumpAndSettle();

      expect(read.roomRequests, <String>['room-a', 'room-b']);
      expect(read.threadRequests, <String>['thread-a', 'thread-b']);
      expect(_visibleChat(tester).thread.id, 'thread-b');
      expect(_visibleChat(tester).room?.id, 'room-b');
    },
  );

  testWidgets(
    'production router recreates IQ detail state when questionId changes',
    (WidgetTester tester) async {
      final _RecordingIndividualQuestions questions =
          _RecordingIndividualQuestions(<String, IndividualQuestion>{
        'question-a': _individualQuestion('question-a', '가 질문'),
        'question-b': _individualQuestion('question-b', '나 질문'),
      });
      final AppDependencies dependencies = testAppDependencies(
        auth: TestAppAuth(
          role: AppRole.student,
          userId: 'student-user',
          account: AccountState.active,
        ),
        individualQuestions: questions,
      );
      final GoRouter router = await _pumpProductionRoute(
        tester,
        dependencies,
        AppRoutePaths.individualQuestion('question-a'),
      );

      final State<StatefulWidget> firstState =
          tester.state<State<StatefulWidget>>(find.byType(IqDetailScreen));
      expect(questions.fetchRequests, <String>['question-a']);
      expect(find.text('가 질문'), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'A 질문의 작성 중 메시지');

      // Re-requesting the same logical entity must retain its state and data.
      router.go(AppRoutePaths.individualQuestion('question-a'));
      await tester.pumpAndSettle();
      expect(questions.fetchRequests, <String>['question-a']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'A 질문의 작성 중 메시지',
      );

      router.go(AppRoutePaths.individualQuestion('question-b'));
      await tester.pumpAndSettle();

      expect(questions.fetchRequests, <String>['question-a', 'question-b']);
      expect(find.text('가 질문'), findsNothing);
      expect(find.text('나 질문'), findsWidgets);
      expect(
        identical(
          firstState,
          tester.state<State<StatefulWidget>>(find.byType(IqDetailScreen)),
        ),
        isFalse,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
    },
  );
}

Future<GoRouter> _pumpProductionRoute(
  WidgetTester tester,
  AppDependencies dependencies,
  String location,
) async {
  final GoRouter router = AppRouter.create(dependencies);
  addTearDown(router.dispose);
  router.go(location);
  await tester.pumpWidget(
    AppScope(
      dependencies: dependencies,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

ChatScreen _visibleChat(WidgetTester tester) =>
    tester.widget<ChatScreen>(find.byType(ChatScreen));

class _RecordingMentorDirectory extends MentorDirectoryRepository {
  _RecordingMentorDirectory(this.items);

  final Map<String, MentorListItem> items;
  final List<String> detailRequests = <String>[];

  @override
  Future<MentorListItem?> fetchListItemById(String mentorId) async {
    detailRequests.add(mentorId);
    return items[mentorId];
  }

  @override
  Future<MentorDetailExtras> fetchExtras(
    String mentorId, {
    double? knownAvgRating,
    int? knownReviewCount,
  }) async =>
      const MentorDetailExtras();
}

class _EmptyMentorFavorites extends MentorFavoritesRepository {
  const _EmptyMentorFavorites();

  @override
  bool get isLoggedIn => true;

  @override
  Future<MentorFavoritesLoad> loadMyFavoriteMentorIds() async =>
      const MentorFavoritesLoaded(<String>{});
}

class _RecordingQuestionRoomRead extends QuestionRoomReadRepository {
  _RecordingQuestionRoomRead({
    required this.rooms,
    required this.threadRows,
  });

  final Map<String, Room> rooms;
  final Map<String, QuestionThread> threadRows;
  final List<String> roomRequests = <String>[];
  final List<String> threadRequests = <String>[];

  @override
  Future<Room?> roomById(String roomId) async {
    roomRequests.add(roomId);
    return rooms[roomId];
  }

  @override
  Future<QuestionThread?> threadById(String threadId) async {
    threadRequests.add(threadId);
    return threadRows[threadId];
  }

  @override
  Future<List<QuestionMessage>> recentMessages(
    String threadId, {
    required int limit,
  }) async =>
      const <QuestionMessage>[];

  @override
  Future<List<QuestionAttachment>> attachments(String threadId) async =>
      const <QuestionAttachment>[];
}

class _MentorLookup extends MentorLookupRepository {
  const _MentorLookup();

  @override
  Future<MentorPublic?> fetch(String mentorId) async =>
      MentorPublic(id: mentorId, nickname: '$mentorId 이름');
}

class _RecordingIndividualQuestions extends IndividualQuestionRepository {
  _RecordingIndividualQuestions(this.questions);

  final Map<String, IndividualQuestion> questions;
  final List<String> fetchRequests = <String>[];

  @override
  Future<IndividualQuestion?> fetch(String questionId) async {
    fetchRequests.add(questionId);
    return questions[questionId];
  }

  @override
  Future<List<IqMessage>> listMessages(String questionId) async =>
      const <IqMessage>[];

  @override
  Future<List<IqAttachment>> listAttachments(String questionId) async =>
      const <IqAttachment>[];
}

final DateTime _timestamp = DateTime.utc(2026, 9, 5);

Room _room(String id, String mentorId) => Room(
      id: id,
      studentId: 'student-user',
      mentorId: mentorId,
      createdAt: _timestamp,
      updatedAt: _timestamp,
    );

QuestionThread _thread(String id, String roomId) => QuestionThread(
      id: id,
      roomId: roomId,
      title: id,
      status: ThreadStatus.open,
      masteryStatus: MasteryStatus.unknown,
      createdAt: _timestamp,
      updatedAt: _timestamp,
    );

IndividualQuestion _individualQuestion(String id, String title) =>
    IndividualQuestion(
      id: id,
      studentId: 'student-user',
      type: IndividualQuestionType.open,
      status: IndividualQuestionStatus.answered,
      title: title,
      body: '$title 본문',
      priceCents: 10000,
      createdAt: _timestamp,
    );
