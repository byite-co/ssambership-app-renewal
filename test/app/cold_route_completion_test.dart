import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ssambership_app/app/app_route_paths.dart';
import 'package:ssambership_app/app/app_scope.dart';
import 'package:ssambership_app/app/router.dart';
import 'package:ssambership_app/core/auth/account_status.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_read_repository.dart';
import 'package:ssambership_app/features/community/data/community_write_repository.dart';
import 'package:ssambership_app/features/community/ui/widgets/content_policy_gate.dart';
import 'package:ssambership_app/features/individual_question/data/individual_question_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/mentors/data/mentor_directory_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_favorites_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/data/mypage_repository.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';
import 'package:ssambership_app/features/notifications/data/notifications_repository.dart';
import 'package:ssambership_app/features/question_room/data/models/room.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';

import '../community/fakes.dart';
import '../support/app_scope_test_harness.dart';

const MyPageData _studentMyPage = MyPageData(
  role: AppRole.student,
  profile: MyProfile(name: '탐색학생', roleLabel: '학생'),
);

const MyPageData _mentorMyPage = MyPageData(
  role: AppRole.mentor,
  profile: MyProfile(name: '탐색멘토', roleLabel: '멘토'),
  mentor: MentorDashboard(
    studentCount: 1,
    pendingAnswers: 1,
    latestSettlementCents: 10000,
  ),
);

const MentorListItem _mentor = MentorListItem(
  id: 'mentor-1',
  nickname: '탐색멘토',
);

final BoardPost _board = BoardPost(
  id: 'board-1',
  title: '콜드 게시글',
  body: '상세 본문',
  authorLabel: '탐색학생',
  authorRole: 'student',
  likeCount: 0,
  commentCount: 0,
  viewCount: 0,
  createdAt: DateTime(2026, 9, 5),
);

final IndividualQuestion _question = IndividualQuestion(
  id: 'question-1',
  studentId: 'student-1',
  type: IndividualQuestionType.open,
  status: IndividualQuestionStatus.released,
  title: '콜드 개별질문',
  body: '질문 본문',
  priceCents: 10000,
  createdAt: DateTime(2026, 9, 5),
);

void main() {
  tearDown(() => ContentPolicyGate.agreedThisSession = false);

  testWidgets('cold /me 알림 동작은 마지막 page를 pop하지 않고 알림 탭으로 간다', (
    WidgetTester tester,
  ) async {
    _useLargeSurface(tester);
    final _RouterHarness harness = _harness(
      role: AppRole.student,
      myPage: const _FixedMyPage(_studentMyPage),
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    harness.router.go(AppRoutePaths.myPage);
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.myPage);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.text('알림'));
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.notifications);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      4,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold /me 받은 질문 동작은 HomeShell hand-off 없이 질문방으로 간다', (
    WidgetTester tester,
  ) async {
    _useLargeSurface(tester);
    final _RouterHarness harness = _harness(
      role: AppRole.mentor,
      myPage: const _FixedMyPage(_mentorMyPage),
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    harness.router.go(AppRoutePaths.myPage);
    await tester.pumpAndSettle();

    await tester.tap(find.text('받은 질문 보기'));
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.rooms);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold 멘토 상세의 back과 질문방 CTA는 안전한 URL로 완료된다', (
    WidgetTester tester,
  ) async {
    _useLargeSurface(tester);
    final _RouterHarness harness = _harness(
      role: AppRole.student,
      mentorDirectory: const _FixedMentorDirectory(),
      mentorFavorites: const _FixedMentorFavorites(),
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    harness.router.go(AppRoutePaths.mentor(_mentor.id));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.mentors);

    harness.router.go(AppRoutePaths.mentor(_mentor.id));
    await tester.pumpAndSettle();
    await tester.tap(find.text('질문방으로'));
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.rooms);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold 게시글 작성은 back과 성공 모두 커뮤니티 URL로 완료된다', (
    WidgetTester tester,
  ) async {
    _useLargeSurface(tester);
    final FakeCommunityWrite write = FakeCommunityWrite(uid: 'student-1');
    final _RouterHarness harness = _harness(
      role: AppRole.student,
      communityWrite: write,
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    harness.router.go(AppRoutePaths.newBoardPost);
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.community);

    harness.router.go(AppRoutePaths.newBoardPost);
    await tester.pumpAndSettle();
    ContentPolicyGate.agreedThisSession = true;
    await tester.enterText(find.byType(TextField).at(0), '콜드 작성 제목');
    await tester.enterText(find.byType(TextField).at(1), '콜드 작성 본문');
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();

    expect(write.postCalls, 1);
    expect(_path(harness.router), AppRoutePaths.community);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold 숏폼 작성의 명시적 취소도 커뮤니티 URL로 완료된다', (
    WidgetTester tester,
  ) async {
    _useLargeSurface(tester);
    final _RouterHarness harness = _harness(role: AppRole.mentor);
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    harness.router.go(AppRoutePaths.newShortform);
    await tester.pumpAndSettle();

    expect(find.text('로그인이 필요해요'), findsOneWidget);
    await tester.tap(find.byTooltip('취소'));
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.community);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold 게시글 상세의 PopScope back은 커뮤니티 URL로 완료된다', (
    WidgetTester tester,
  ) async {
    _useLargeSurface(tester);
    final _RouterHarness harness = _harness(
      role: AppRole.student,
      communityRead: const _FixedCommunityRead(),
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    harness.router.go(AppRoutePaths.boardPost(_board.id));
    await tester.pumpAndSettle();

    expect(find.text(_board.title), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.community);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold 개별질문 상세의 PopScope back은 IQ 탭 URL로 완료된다', (
    WidgetTester tester,
  ) async {
    _useLargeSurface(tester);
    final _RouterHarness harness = _harness(
      role: AppRole.student,
      individualQuestions: const _FixedIndividualQuestions(),
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    harness.router.go(AppRoutePaths.individualQuestion(_question.id));
    await tester.pumpAndSettle();

    expect(find.text(_question.title), findsWidgets);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(_path(harness.router), AppRoutePaths.individualQuestions);
    expect(tester.takeException(), isNull);
  });

  testWidgets('셸에서 push한 작성 route는 기존 URL과 typed 결과를 보존한다', (
    WidgetTester tester,
  ) async {
    _useLargeSurface(tester);
    final FakeCommunityWrite write = FakeCommunityWrite(uid: 'student-1');
    final _RouterHarness harness = _harness(
      role: AppRole.student,
      communityWrite: write,
    );
    addTearDown(harness.router.dispose);

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    expect(_path(harness.router), AppRoutePaths.rooms);

    final Future<bool?> result =
        harness.router.push<bool>(AppRoutePaths.newBoardPost);
    await tester.pumpAndSettle();
    ContentPolicyGate.agreedThisSession = true;
    await tester.enterText(find.byType(TextField).at(0), 'push 작성 제목');
    await tester.enterText(find.byType(TextField).at(1), 'push 작성 본문');
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(write.postCalls, 1);
    expect(_path(harness.router), AppRoutePaths.rooms);
    expect(tester.takeException(), isNull);
  });
}

void _useLargeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

_RouterHarness _harness({
  required AppRole role,
  MyPageRepository myPage = const _FixedMyPage(_studentMyPage),
  MentorDirectoryRepository mentorDirectory = const _FixedMentorDirectory(),
  MentorFavoritesRepository mentorFavorites = const _FixedMentorFavorites(),
  CommunityReadRepository communityRead = const FakeCommunityRead(),
  CommunityWriteRepository? communityWrite,
  IndividualQuestionRepository individualQuestions =
      const IndividualQuestionRepository(),
}) {
  final TestAppAuth auth = TestAppAuth(
    role: role,
    userId: '${role.name}-1',
    account: AccountState.active,
  );
  final AppDependencies base = testAppDependencies(auth: auth);
  final AppDependencies dependencies = AppDependencies(
    auth: auth,
    supabaseClient: () => null,
    questionRoomRead: const _EmptyQuestionRoomRead(),
    myPage: myPage,
    communityRead: communityRead,
    communityWrite:
        communityWrite ?? FakeCommunityWrite(uid: auth.currentUserId),
    individualQuestions: individualQuestions,
    mentorDirectory: mentorDirectory,
    mentorFavorites: mentorFavorites,
    notifications: const _EmptyNotifications(),
    attachmentUrlResolver: base.attachmentUrlResolver,
    notificationBadge: base.notificationBadge,
    deletionNotice: base.deletionNotice,
    versionGate: base.versionGate,
  );
  final GoRouter router = AppRouter.create(dependencies);
  return _RouterHarness(
    router: router,
    app: AppScope(
      dependencies: dependencies,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

class _RouterHarness {
  const _RouterHarness({required this.router, required this.app});

  final GoRouter router;
  final Widget app;
}

class _FixedMyPage extends MyPageRepository {
  const _FixedMyPage(this.data);

  final MyPageData data;

  @override
  Future<MyPageData> load() async => data;
}

class _FixedMentorDirectory extends MentorDirectoryRepository {
  const _FixedMentorDirectory();

  @override
  Future<MentorDirectoryResult> listComplete() async =>
      const MentorDirectoryResult(
        items: <MentorListItem>[_mentor],
        incomplete: false,
      );

  @override
  Future<MentorListItem?> fetchListItemById(String mentorId) async =>
      mentorId == _mentor.id ? _mentor : null;

  @override
  Future<MentorDetailExtras> fetchExtras(
    String mentorId, {
    double? knownAvgRating,
    int? knownReviewCount,
  }) async =>
      const MentorDetailExtras(alreadySubscribed: true);
}

class _FixedMentorFavorites extends MentorFavoritesRepository {
  const _FixedMentorFavorites();

  @override
  bool get isLoggedIn => true;

  @override
  Future<MentorFavoritesLoad> loadMyFavoriteMentorIds() async =>
      const MentorFavoritesLoaded(<String>{});
}

class _FixedCommunityRead extends FakeCommunityRead {
  const _FixedCommunityRead();

  @override
  Future<BoardPost?> boardPostById(String postId) async =>
      postId == _board.id ? _board : null;
}

class _FixedIndividualQuestions extends IndividualQuestionRepository {
  const _FixedIndividualQuestions();

  @override
  Future<IndividualQuestion?> fetch(String questionId) async =>
      questionId == _question.id ? _question : null;

  @override
  Future<List<IqMessage>> listMessages(String questionId) async =>
      const <IqMessage>[];

  @override
  Future<List<IqAttachment>> listAttachments(String questionId) async =>
      const <IqAttachment>[];
}

class _EmptyQuestionRoomRead extends QuestionRoomReadRepository {
  const _EmptyQuestionRoomRead();

  @override
  Future<List<Room>> myRooms() async => const <Room>[];
}

class _EmptyNotifications implements NotificationsRepository {
  const _EmptyNotifications();

  @override
  Future<NotificationsPage> fetch({
    NotificationCursor? after,
    int pageSize = 20,
  }) async =>
      const NotificationsPage(items: <AppNotification>[], hasNext: false);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;

  @override
  Future<int> unreadCount() async => 0;
}

String _path(GoRouter router) => router.routeInformationProvider.value.uri.path;
