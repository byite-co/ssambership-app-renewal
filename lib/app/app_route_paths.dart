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
