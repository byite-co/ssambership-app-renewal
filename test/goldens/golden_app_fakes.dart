import 'package:flutter/foundation.dart';
import 'package:ssambership_app/app/app_scope.dart';
import 'package:ssambership_app/core/auth/account_status.dart';
import 'package:ssambership_app/core/auth/app_auth.dart';
import 'package:ssambership_app/core/auth/auth_service.dart' show AppRole;
import 'package:ssambership_app/core/auth/deletion_notice_controller.dart';
import 'package:ssambership_app/core/entitlement/subscription_summary.dart';
import 'package:ssambership_app/core/entitlement/subscription_summary_port.dart';
import 'package:ssambership_app/features/mypage/data/account_deletion_repository.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/data/mypage_repository.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';
import 'package:ssambership_app/features/notifications/data/notification_badge_controller.dart';
import 'package:ssambership_app/features/notifications/data/notifications_repository.dart';
import 'package:ssambership_app/features/question_room/data/mentor_lookup_repository.dart';
import 'package:ssambership_app/features/question_room/data/question_room_read_repository.dart';
import 'package:ssambership_app/features/question_room/data/student_lookup_repository.dart';

/// AppScope 용 fake 묶음 — 네트워크·인증·전역 싱글턴에 닿지 않는다.
///
/// 골든은 [goldenDependencies] 로 만든 [AppDependencies] 를 `pumpGoldenScreen` 에 넘긴다.
/// 넘기지 않은 항목은 운영 기본값(백엔드 미연결 → 오류 표시)이라, 빠진 fake 는
/// 화면에서 드러난다.

/// 인증·역할 fake — 값을 직접 정한다(세션 없음 = userId null).
class FakeAppAuth extends ChangeNotifier implements AppAuth {
  FakeAppAuth({
    this.role = AppRole.student,
    this.userId,
    this.guest = false,
    this.account = AccountState.active,
  });

  AppRole role;
  String? userId;
  bool guest;
  AccountState account;
  int signOutCalls = 0;

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
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<void> reloadProfile() async {}
}

/// 멘토 표시명 조회 fake.
class GoldenMentorLookup extends MentorLookupRepository {
  const GoldenMentorLookup(this.byId);
  final Map<String, MentorPublic> byId;

  @override
  Future<MentorPublic?> fetch(String mentorId) async => byId[mentorId];

  @override
  Future<Map<String, MentorPublic>> fetchMany(Iterable<String> ids) async =>
      <String, MentorPublic>{
        for (final String id in ids)
          if (byId[id] != null) id: byId[id]!,
      };
}

/// 학생 표시명 조회 fake.
class GoldenStudentLookup extends StudentLookupRepository {
  const GoldenStudentLookup(this.byId);
  final Map<String, StudentPublic> byId;

  @override
  Future<StudentPublic?> fetch(String studentId) async => byId[studentId];

  @override
  Future<Map<String, StudentPublic>> fetchMany(Iterable<String> ids) async =>
      <String, StudentPublic>{
        for (final String id in ids)
          if (byId[id] != null) id: byId[id]!,
      };
}

/// 구독 요약 fake — 멘토 id → 요약.
class GoldenSubscriptions implements SubscriptionSummaryPort {
  const GoldenSubscriptions(this.byMentor);
  final Map<String, SubscriptionSummary> byMentor;

  @override
  Future<Map<String, SubscriptionSummary>> fetchForStudent(
          String studentId) async =>
      byMentor;
}

/// 마이페이지 레포 fake — 고정 데이터.
class GoldenMyPageRepository extends MyPageRepository {
  const GoldenMyPageRepository(this.data);
  final MyPageData data;

  @override
  Future<MyPageData> load() async => data;
}

/// 알림 없음 — 배지 컨트롤러용.
class _NoNotifications implements NotificationsRepository {
  const _NoNotifications();

  @override
  Future<NotificationsPage> fetch(
          {NotificationCursor? after, int pageSize = 20}) async =>
      const NotificationsPage(items: <AppNotification>[], hasNext: false);

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<int> markAllRead() async => 0;

  @override
  Future<int> unreadCount() async => 0;
}

/// 탈퇴 잡 없음 — 배너 컨트롤러용.
class _NoDeletion implements AccountDeletionPort {
  const _NoDeletion();

  @override
  Future<DeletionStatusResult> fetchStatus() async =>
      const DeletionStatusResult(
          exists: false, writeBlocked: false, canCancel: false);

  @override
  Future<DeletionCancelResult> cancelDeletion() async =>
      const DeletionCancelResult(ok: false);

  @override
  Future<DeletionRequestOutcome> requestDeletion() =>
      throw UnsupportedError('golden fixture');

  @override
  Future<DeletionRequestOutcome> requestDeletionWithForfeitConsent(
          {required int acknowledgedBalanceCents}) =>
      throw UnsupportedError('golden fixture');
}

/// 골든용 의존성 묶음. 알림 배지·탈퇴 배너는 항상 '없음' fake 로 채운다.
AppDependencies goldenDependencies({
  required AppAuth auth,
  QuestionRoomReadRepository? questionRoomRead,
  MentorLookupRepository? mentorLookup,
  StudentLookupRepository? studentLookup,
  SubscriptionSummaryPort? subscriptions,
  MyPageRepository? myPage,
}) =>
    AppDependencies(
      auth: auth,
      supabaseClient: () => null,
      questionRoomRead: questionRoomRead ?? const QuestionRoomReadRepository(),
      mentorLookup: mentorLookup ?? const GoldenMentorLookup(<String, MentorPublic>{}),
      studentLookup:
          studentLookup ?? const GoldenStudentLookup(<String, StudentPublic>{}),
      subscriptions: subscriptions ??
          const GoldenSubscriptions(<String, SubscriptionSummary>{}),
      myPage: myPage ?? const MyPageRepository(),
      notificationBadge:
          NotificationBadgeController(repository: const _NoNotifications()),
      deletionNotice: DeletionNoticeController(port: const _NoDeletion()),
    );
