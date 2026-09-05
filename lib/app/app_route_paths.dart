/// Canonical in-app URL paths.
///
/// Keep path construction here so navigation call sites pass scalar identifiers
/// only. Route registration is intentionally separate in `router.dart`.
class AppRoutePaths {
  AppRoutePaths._();

  static const String root = '/';
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String home = '/home';
  static const String blocked = '/blocked';

  static const String rooms = '/rooms';
  static const String individualQuestions = '/iq';
  static const String mentors = '/mentors';
  static const String settlements = '/settlements';
  static const String community = '/community';
  static const String notifications = '/notifications';
  static const String myPage = '/me';

  static const String boardPosts = '$community/boards';
  static const String shortforms = '$community/shortforms';

  static const String newBoardPost = '$boardPosts/new';
  static const String newShortform = '$shortforms/new';
  static const String profileEdit = '$myPage/profile';
  static const String accountDeletion = '$myPage/account-deletion';
  static const String blockedUsers = '$myPage/blocked-users';

  // ── A-4a 기능 개방(앱 단독분) — A-3 future slot 을 그대로 쓴다 ──
  /// 멘토 정산 허브(이번 달 금액·소스별·계좌 경고·멘토 관리 진입).
  static const String settlementHistory = '$settlements/history';

  /// 멘토 정산 계좌 등록.
  static const String settlementAccount = '$settlements/account';

  /// 멘토 정산 건별 내역.
  static const String settlementLines = '$settlements/lines';

  /// 멘토 자기 관리 루트(요금제·학력 인증·학적 변경·프로필 편집).
  static const String mentorProfile = '/profile';
  static const String mentorPlans = '$mentorProfile/plans';
  static const String mentorEducationVerification =
      '$mentorProfile/education-verification';
  static const String mentorAcademicRecordChange =
      '$mentorProfile/academic-record-change';
  static const String mentorProfileEdit = '$mentorProfile/edit';

  /// 학생 개별질문 등록(네이티브). `?mentor=` 로 지정형.
  static const String newIndividualQuestion = '$individualQuestions/new';

  static const String devGallery = '/dev/gallery';
  static const String devS3 = '/dev/s3';

  static String room(String roomId) => '$rooms/${_segment(roomId)}';

  static String roomThreads(String roomId) => '${room(roomId)}/threads';

  static String newRoomThread(String roomId) => '${roomThreads(roomId)}/new';

  static String roomThread(String roomId, String threadId) =>
      '${roomThreads(roomId)}/${_segment(threadId)}';

  static String roomNotes(String roomId) => '${room(roomId)}/notes';

  static String freeQuestion(String roomId) => '${room(roomId)}/free-question';

  static String roomAttachment(
    String roomId,
    String threadId,
    String attachmentId,
  ) =>
      '${roomThread(roomId, threadId)}/attachments/${_segment(attachmentId)}';

  static String individualQuestion(String questionId) =>
      '$individualQuestions/${_segment(questionId)}';

  /// 멘토 지정형 개별질문 등록 URL(`/iq/new?mentor=<id>`).
  static String newIndividualQuestionFor(String mentorId) => Uri(
        path: newIndividualQuestion,
        queryParameters: <String, String>{'mentor': mentorId},
      ).toString();

  static String mentor(String mentorId) => '$mentors/${_segment(mentorId)}';

  static String boardPost(String postId) => '$boardPosts/${_segment(postId)}';

  static String editBoardPost(String postId) => '${boardPost(postId)}/edit';

  static String shortform(String shortformId) =>
      '$shortforms/${_segment(shortformId)}';

  static String loginWithNotice(String notice) => Uri(
        path: login,
        queryParameters: <String, String>{'notice': notice},
      ).toString();

  static String _segment(String value) => Uri.encodeComponent(value);
}
