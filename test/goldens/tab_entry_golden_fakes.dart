import 'package:ssambership_app/features/community/data/community_models.dart';
import 'package:ssambership_app/features/community/data/community_read_repository.dart';
import 'package:ssambership_app/features/community/data/community_write_repository.dart';
import 'package:ssambership_app/features/individual_question/data/individual_question_repository.dart';
import 'package:ssambership_app/features/individual_question/data/models/individual_question_models.dart';
import 'package:ssambership_app/features/mentors/data/mentor_directory_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_favorites_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';
import 'package:ssambership_app/features/notifications/data/notifications_realtime.dart';
import 'package:ssambership_app/features/notifications/data/notifications_repository.dart';

import 'golden_fixtures.dart';

DateTime _at(int day, [int hour = 9, int minute = 0]) =>
    DateTime(2026, 7, day, hour, minute);

class GoldenCommunityRead extends CommunityReadRepository {
  const GoldenCommunityRead({
    this.boardsList = const <BoardPost>[],
    this.shortformsList = const <ShortformPost>[],
    this.activity = const MyActivity(),
  });

  final List<BoardPost> boardsList;
  final List<ShortformPost> shortformsList;
  final MyActivity activity;

  CommunityPage<T> _page<T>(List<T> all, int? limit, int offset) {
    final int start = offset.clamp(0, all.length);
    final int end =
        limit == null ? all.length : (offset + limit).clamp(start, all.length);
    final List<T> items = all.sublist(start, end);
    return CommunityPage<T>(
      items: items,
      rawCount: items.length,
      nextOffset: offset + items.length,
      hasMore: limit != null && items.length == limit,
    );
  }

  @override
  Future<CommunityPage<BoardPost>> boards({
    String? category,
    int? limit,
    int offset = 0,
  }) async {
    final List<BoardPost> filtered = category == null
        ? boardsList
        : boardsList
            .where((BoardPost post) => post.category == category)
            .toList(growable: false);
    return _page<BoardPost>(filtered, limit, offset);
  }

  @override
  Future<CommunityPage<ShortformPost>> shortforms({
    int? limit,
    int offset = 0,
  }) async =>
      _page<ShortformPost>(shortformsList, limit, offset);

  @override
  Future<List<CommunityComment>> comments(
    CommunityPostType type,
    String postId, {
    int? limit,
    int offset = 0,
  }) async =>
      const <CommunityComment>[];

  @override
  Future<Set<String>> myBoardReactionIds(
    String reactionType, {
    String? postId,
  }) async =>
      <String>{};

  @override
  Future<Set<String>> myShortformReactionIds(
    String reactionType, {
    String? shortformId,
  }) async =>
      <String>{};

  @override
  Future<MyActivity> myActivity() async => activity;
}

class GoldenCommunityWrite extends CommunityWriteRepository {
  const GoldenCommunityWrite();
}

class GoldenIndividualQuestions extends IndividualQuestionRepository {
  const GoldenIndividualQuestions();
}

class GoldenMentorDirectory extends MentorDirectoryRepository {
  const GoldenMentorDirectory(this.items);

  final List<MentorListItem> items;

  @override
  Future<MentorDirectoryResult> listComplete() async => MentorDirectoryResult(
        items: items,
        incomplete: false,
      );
}

class GoldenMentorFavorites extends MentorFavoritesRepository {
  const GoldenMentorFavorites({
    this.loggedIn = true,
    this.ids = const <String>{},
  });

  final bool loggedIn;
  final Set<String> ids;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  Future<MentorFavoritesLoad> loadMyFavoriteMentorIds() async => loggedIn
      ? MentorFavoritesLoaded(Set<String>.of(ids))
      : const MentorFavoritesLoggedOut();

  @override
  Future<bool> add(String mentorId) async => true;

  @override
  Future<bool> remove(String mentorId) async => true;
}

class GoldenNotifications implements NotificationsRepository {
  const GoldenNotifications(this.items);

  final List<AppNotification> items;

  @override
  Future<NotificationsPage> fetch({
    NotificationCursor? after,
    int pageSize = 20,
  }) async =>
      NotificationsPage(items: items, hasNext: false);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async =>
      items.where((AppNotification item) => !item.isRead).length;

  @override
  Future<int> unreadCount() async =>
      items.where((AppNotification item) => !item.isRead).length;
}

class GoldenNotificationsRealtime implements NotificationsRealtimePort {
  @override
  void start({
    required void Function(Map<String, dynamic> row) onInsert,
    void Function()? onReconnected,
  }) {}

  @override
  Future<void> dispose() async {}
}

List<IndividualQuestion> goldenStudentIndividualQuestions() =>
    <IndividualQuestion>[
      IndividualQuestion(
        id: 'iq-s1',
        studentId: kStudentId,
        type: IndividualQuestionType.direct,
        status: IndividualQuestionStatus.answered,
        title: '미적분 극한 풀이를 확인해 주세요',
        body: '풀이 본문',
        priceCents: 500000,
        designatedMentorId: kMentorId,
        subject: 'math_calculus',
        createdAt: _at(3),
      ),
      IndividualQuestion(
        id: 'iq-s2',
        studentId: kStudentId,
        type: IndividualQuestionType.open,
        status: IndividualQuestionStatus.open,
        title: '영어 빈칸 추론 접근법이 궁금해요',
        body: '풀이 본문',
        priceCents: 300000,
        subject: 'english',
        requiredSchoolTier: '서연고',
        createdAt: _at(2),
      ),
      IndividualQuestion(
        id: 'iq-s3',
        studentId: kStudentId,
        type: IndividualQuestionType.open,
        status: IndividualQuestionStatus.released,
        title: '비문학 선지 판단 기준',
        body: '풀이 본문',
        priceCents: 400000,
        claimedMentorId: kMentor2Id,
        subject: 'korean_reading',
        createdAt: _at(1),
      ),
    ];

List<IndividualQuestion> goldenMentorIndividualQuestions() =>
    <IndividualQuestion>[
      IndividualQuestion(
        id: 'iq-m1',
        studentId: kStudentId,
        type: IndividualQuestionType.direct,
        status: IndividualQuestionStatus.assigned,
        title: '기하 벡터 내적 풀이 질문',
        body: '풀이 본문',
        priceCents: 500000,
        designatedMentorId: kMentorId,
        subject: 'math_geometry',
        createdAt: _at(2),
      ),
      IndividualQuestion(
        id: 'iq-m2',
        studentId: kStudent2Id,
        type: IndividualQuestionType.open,
        status: IndividualQuestionStatus.answered,
        title: '확률 조건부확률 풀이 검토',
        body: '풀이 본문',
        priceCents: 450000,
        claimedMentorId: kMentorId,
        subject: 'math_probability',
        createdAt: _at(1),
      ),
    ];

List<OpenIndividualQuestion> goldenOpenIndividualQuestions() =>
    <OpenIndividualQuestion>[
      OpenIndividualQuestion(
        id: 'iq-open-1',
        title: '수열 점화식 풀이를 도와주세요',
        priceCents: 300000,
        subject: 'math_1',
        requiredMajorCategory: '자연계',
        createdAt: _at(3),
      ),
    ];

List<MentorListItem> goldenMentorDirectoryItems() => <MentorListItem>[
      MentorListItem(
        id: kMentorId,
        nickname: kMentorName,
        createdAt: _at(3),
        avgRating: 4.9,
        reviewCount: 28,
        profile: const MentorProfileInfo(
          userId: kMentorId,
          universityName: '서울대학교',
          departmentName: '수학교육과',
          teachingSubjects: <String>['math', 'math_calculus'],
          introLine: '개념부터 풀이 습관까지 차근차근 함께해요.',
          schoolVerified: true,
        ),
      ),
      MentorListItem(
        id: kMentor2Id,
        nickname: '박영어',
        createdAt: _at(2),
        avgRating: 4.8,
        reviewCount: 17,
        profile: const MentorProfileInfo(
          userId: kMentor2Id,
          universityName: '연세대학교',
          departmentName: '영어영문학과',
          teachingSubjects: <String>['english'],
          introLine: '근거를 찾는 독해 방법을 알려드려요.',
          schoolVerified: true,
        ),
      ),
      MentorListItem(
        id: kMentor3Id,
        nickname: '최과학',
        createdAt: _at(1),
        avgRating: 4.7,
        reviewCount: 9,
        profile: const MentorProfileInfo(
          userId: kMentor3Id,
          universityName: '고려대학교',
          departmentName: '생명과학부',
          teachingSubjects: <String>['science'],
          introLine: '과학 개념을 문제에 연결하는 연습을 합니다.',
          schoolVerified: true,
        ),
      ),
    ];

List<ShortformPost> goldenShortforms() => <ShortformPost>[
      ShortformPost(
        id: 'sf1',
        title: '오답노트, 이렇게 복습해 보세요',
        description: '복습 주기를 정하는 방법',
        category: 'study',
        authorLabel: kMentorName,
        authorRole: 'mentor',
        likeCount: 28,
        viewCount: 341,
        createdAt: _at(3),
      ),
      ShortformPost(
        id: 'sf2',
        title: '수학 실수를 줄이는 세 가지 체크',
        description: '시험 직전 확인할 습관',
        category: 'study',
        authorLabel: '박멘토',
        authorRole: 'mentor',
        likeCount: 17,
        viewCount: 208,
        createdAt: _at(2),
      ),
    ];

List<BoardPost> goldenBoards() => <BoardPost>[
      BoardPost(
        id: 'board1',
        title: '매일 공부 시작 시간을 지키는 방법',
        body: '작은 단위로 시작해 보세요.',
        category: 'study',
        authorLabel: '익명 학생',
        authorRole: 'student',
        likeCount: 12,
        commentCount: 4,
        viewCount: 96,
        createdAt: _at(3),
      ),
    ];

List<AppNotification> goldenTabNotifications() => <AppNotification>[
      AppNotification(
        id: 'notification-1',
        eventType: NotificationEventType.questionAnswered,
        title: '답변이 도착했어요',
        body: '삼각함수 합성 질문에 멘토 답변이 등록됐어요.',
        isRead: false,
        createdAt: _at(3, 14, 5),
        roomId: kRoomId,
      ),
      AppNotification(
        id: 'notification-2',
        eventType: NotificationEventType.individualQuestionAnswered,
        title: '개별질문 답변 도착',
        body: '미적분 극한 풀이 질문의 답변을 확인해 보세요.',
        isRead: false,
        createdAt: _at(2, 17),
        questionId: 'iq-s1',
      ),
      AppNotification(
        id: 'notification-3',
        eventType: NotificationEventType.subscriptionRenewalUpcoming,
        title: '구독 갱신 안내',
        body: '다음 구독 갱신 예정일을 확인해 주세요.',
        isRead: true,
        createdAt: _at(1, 10),
      ),
    ];
