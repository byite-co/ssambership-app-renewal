import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/app/app_scope.dart';
import 'package:ssambership_app/core/auth/account_status.dart';
import 'package:ssambership_app/core/auth/app_auth.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/core/auth/deletion_notice_controller.dart';
import 'package:ssambership_app/core/version_gate/version_gate_controller.dart';
import 'package:ssambership_app/features/mypage/data/account_deletion_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_directory_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_favorites_repository.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';
import 'package:ssambership_app/features/notifications/data/notification_badge_controller.dart';
import 'package:ssambership_app/features/notifications/data/notifications_repository.dart';
import 'package:ssambership_app/features/question_room/data/attachments/attachment_url_resolver.dart';
import 'package:ssambership_app/features/question_room/data/mentor_lookup_repository.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';

/// Wraps a directly pumped test app in an explicit, backend-free [AppScope].
Widget withTestAppScope(
  Widget child, {
  AppDependencies? dependencies,
  AppAuth? auth,
}) =>
    AppScope(
      dependencies:
          dependencies ?? testAppDependencies(auth: auth ?? TestAppAuth()),
      child: child,
    );

/// Pumps a widget with the explicit test scope as the outermost ancestor.
extension AppScopeWidgetTester on WidgetTester {
  Future<void> pumpScopedWidget(Widget widget) =>
      pumpWidget(withTestAppScope(widget));
}

/// Minimal dependency graph for widget tests that do not exercise app services.
AppDependencies testAppDependencies({
  required AppAuth auth,
  QuestionRoomReadRepository questionRoomRead =
      const QuestionRoomReadRepository(),
  MentorLookupRepository mentorLookup = const MentorLookupRepository(),
  MentorDirectoryRepository mentorDirectory =
      const MentorDirectoryRepository(),
  MentorFavoritesRepository mentorFavorites =
      const MentorFavoritesRepository(),
}) =>
    AppDependencies(
      auth: auth,
      supabaseClient: () => null,
      questionRoomRead: questionRoomRead,
      mentorLookup: mentorLookup,
      mentorDirectory: mentorDirectory,
      mentorFavorites: mentorFavorites,
      attachmentUrlResolver:
          AttachmentUrlResolver(const _UnavailableAttachmentBackend()),
      notificationBadge:
          NotificationBadgeController(repository: const _NoNotifications()),
      deletionNotice: DeletionNoticeController(port: const _NoDeletion()),
      versionGate: VersionGateController(platformResolver: () => null),
    );

/// Safe authentication state for tests that only need to satisfy [AppScope].
class TestAppAuth extends ChangeNotifier implements AppAuth {
  TestAppAuth({
    this.role = AppRole.guest,
    this.userId,
    this.guest = false,
    this.account = AccountState.fetchFailed,
  });

  AppRole role;
  String? userId;
  bool guest;
  AccountState account;

  @override
  AppRole get currentRole => role;

  @override
  bool get isGuest => guest;

  @override
  bool get isSignedIn => userId != null;

  @override
  String? get currentUserId => userId;

  @override
  AccountState get accountState => account;

  @override
  String get blockedMessage => account.blockedMessage;

  @override
  bool get isRecoverableBlock => account.isRetryable;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {}

  @override
  void enterAsGuest() {
    guest = true;
    role = AppRole.guest;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> reloadProfile() async {}
}

class _UnavailableAttachmentBackend implements AttachmentUrlBackend {
  const _UnavailableAttachmentBackend();

  @override
  String? get currentUserId => null;

  @override
  Future<String> createSignedUrl(String storagePath, int expiresInSeconds) =>
      throw UnsupportedError(
          'Attachment URLs are not configured for this test.');

  @override
  Future<Uint8List> download(String storagePath) => throw UnsupportedError(
      'Attachment downloads are not configured for this test.');
}

class _NoNotifications implements NotificationsRepository {
  const _NoNotifications();

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
  Future<int> unreadCount() => throw UnsupportedError(
      'Notification badges are not configured for this test.');
}

class _NoDeletion implements AccountDeletionPort {
  const _NoDeletion();

  @override
  Future<DeletionStatusResult> fetchStatus() async =>
      const DeletionStatusResult(
        exists: false,
        writeBlocked: false,
        canCancel: false,
      );

  @override
  Future<DeletionCancelResult> cancelDeletion() async =>
      const DeletionCancelResult(ok: false);

  @override
  Future<DeletionRequestOutcome> requestDeletion() => throw UnsupportedError(
      'Account deletion is not configured for this test.');

  @override
  Future<DeletionRequestOutcome> requestDeletionWithForfeitConsent({
    required int acknowledgedBalanceCents,
  }) =>
      throw UnsupportedError(
          'Account deletion is not configured for this test.');
}
