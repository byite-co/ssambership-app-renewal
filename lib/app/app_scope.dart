import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../core/auth/app_auth.dart';
import '../core/auth/auth_service.dart';
import '../core/auth/deletion_notice_controller.dart';
import '../core/entitlement/subscription_summary_port.dart';
import '../core/supabase/supabase_client.dart';
import '../core/version_gate/version_gate_controller.dart';
import '../features/community/data/community_read_repository.dart';
import '../features/community/data/community_write_repository.dart';
import '../features/community/data/user_blocks_repository.dart';
import '../features/individual_question/data/individual_question_repository.dart';
import '../features/individual_question/data/iq_attachments_repository.dart';
import '../features/mentor_console/data/mentor_console_repository.dart';
import '../features/mentors/data/free_question_entry.dart';
import '../features/mentors/data/mentor_directory_repository.dart';
import '../features/mentors/data/mentor_favorites_repository.dart';
import '../features/mypage/data/account_deletion_repository.dart';
import '../features/mypage/data/mypage_repository.dart';
import '../features/mypage/data/notification_settings_repository.dart';
import '../features/mypage/data/profile_edit_repository.dart';
import '../features/notifications/data/notification_badge_controller.dart';
import '../features/notifications/data/notifications_repository.dart';
import '../features/question_room/data/attachments/attachment_upload.dart';
import '../features/question_room/data/attachments/attachment_url_resolver.dart';
import '../features/question_room/data/mentor_lookup_repository.dart';
import '../features/question_room/data/question_room_read_repository.dart';
import '../features/question_room/data/question_room_write_repository.dart';
import '../features/question_room/data/room_safety_repository.dart';
import '../features/question_room/data/student_lookup_repository.dart';

/// 앱 의존성 묶음 — 수동 DI(A-2). 앱 시작 시 한 번 만들어 [AppScope] 로 내려보낸다.
///
/// - 운영: [AppDependencies.production] — 기존 싱글턴·const 레포지토리를 그대로 담는다.
///   (싱글턴 클래스는 없애지 않는다. 화면이 `.instance` 를 **직접** 부르지 않게 하는 것이 목표.)
/// - 테스트·골든: 생성자에 가짜 구현을 넘긴다. 넘기지 않은 항목은 운영 기본값이다 —
///   Supabase 미초기화 환경에서는 그 기본값이 "백엔드 미연결" 오류를 내므로, 골든이
///   빠뜨린 의존성은 화면의 오류 상태로 드러난다(조용히 통과하지 않는다).
///
/// ★ 필요 이상으로 넓히지 않는다: 화면이 실제로 꺼내 쓰는 것만 추가한다.
class AppDependencies {
  AppDependencies({
    required this.auth,
    AccessState Function()? routingAccess,
    SupabaseClient? Function()? supabaseClient,
    this.questionRoomRead = const QuestionRoomReadRepository(),
    this.questionRoomWrite = const QuestionRoomWriteRepository(),
    this.mentorLookup = const MentorLookupRepository(),
    this.studentLookup = const StudentLookupRepository(),
    this.subscriptions = const SupabaseSubscriptionSummaryPort(),
    this.myPage = const MyPageRepository(),
    this.communityRead = const CommunityReadRepository(),
    this.communityWrite = const CommunityWriteRepository(),
    this.individualQuestions = const IndividualQuestionRepository(),
    this.iqAttachments = const SupabaseIqAttachmentsRepository(),
    this.mentorDirectory = const MentorDirectoryRepository(),
    this.mentorFavorites = const MentorFavoritesRepository(),
    this.mentorConsole = const SupabaseMentorConsoleRepository(),
    this.notificationSettings = const NotificationSettingsRepository(),
    this.profileEdit = const ProfileEditRepository(),
    this.accountDeletion = const SupabaseAccountDeletionRepository(),
    this.attachmentUploader = const SupabaseAttachmentUploader(),
    AttachmentUrlResolver? attachmentUrlResolver,
    this.freeQuestionEntry = const SupabaseFreeQuestionEntryRepository(),
    this.notifications = const SupabaseNotificationsRepository(),
    this.roomSafety = const SupabaseRoomSafetyRepository(),
    this.userBlocks = const UserBlocksRepository(),
    NotificationBadgeController? notificationBadge,
    DeletionNoticeController? deletionNotice,
    VersionGateController? versionGate,
  })  : _routingAccess = routingAccess ?? (() => _inferRoutingAccess(auth)),
        _supabaseClient = supabaseClient ?? _productionClient,
        attachmentUrlResolver =
            attachmentUrlResolver ?? AttachmentUrlResolver.supabase(),
        notificationBadge =
            notificationBadge ?? NotificationBadgeController.instance,
        deletionNotice = deletionNotice ?? DeletionNoticeController.instance,
        versionGate = versionGate ?? VersionGateController.instance;

  /// 운영 구성 — main() 이 부팅한 싱글턴들을 그대로 담는다.
  factory AppDependencies.production() {
    final AuthService auth = AuthService.instance;
    return AppDependencies(
      auth: auth,
      routingAccess: () => auth.access,
    );
  }

  static SupabaseClient? _productionClient() => SupabaseInit.clientOrNull;

  /// 인증·역할 상태(종전 `AuthService.instance`).
  final AppAuth auth;

  final AccessState Function() _routingAccess;

  /// 라우터 redirect가 읽는 접근 상태.
  ///
  /// 운영에서는 [AuthService.access]를 그대로 노출하고, 테스트용 fake는 생성자
  /// seam을 주입하거나 인증 인터페이스의 공개 상태에서 보수적으로 추론한다.
  AccessState get routingAccess => _routingAccess();

  final SupabaseClient? Function() _supabaseClient;

  /// Supabase 클라이언트(초기화 전·미설정이면 null — 종전 `SupabaseInit.clientOrNull`).
  /// 화면은 가능하면 [auth] 의 `currentUserId` 등 좁은 게터를 쓰고, 세션 토큰처럼
  /// 클라이언트 자체가 필요한 곳(웹 작성 브릿지)만 이것을 쓴다.
  SupabaseClient? get supabaseClient => _supabaseClient();

  // ── 레포지토리 계열(const 클래스 — 테스트는 extends 로 필요한 메서드만 덮어쓴다) ──
  final QuestionRoomReadRepository questionRoomRead;
  final QuestionRoomWriteRepository questionRoomWrite;
  final MentorLookupRepository mentorLookup;
  final StudentLookupRepository studentLookup;
  final SubscriptionSummaryPort subscriptions;
  final MyPageRepository myPage;
  final CommunityReadRepository communityRead;
  final CommunityWriteRepository communityWrite;
  final IndividualQuestionRepository individualQuestions;
  final IqAttachmentsPort iqAttachments;
  final MentorDirectoryRepository mentorDirectory;
  final MentorFavoritesRepository mentorFavorites;

  /// A-4a 멘토 콘솔(정산 계좌·요금제·정산 조회·학력 인증·학적 변경·프로필).
  final MentorConsolePort mentorConsole;
  final NotificationSettingsPort notificationSettings;
  final ProfileEditRepository profileEdit;
  final AccountDeletionPort accountDeletion;
  final AttachmentUploaderPort attachmentUploader;
  final AttachmentUrlResolver attachmentUrlResolver;
  final FreeQuestionEntryPort freeQuestionEntry;
  final NotificationsRepository notifications;
  final RoomSafetyPort roomSafety;
  final UserBlocksRepository userBlocks;

  // ── 앱 전역 컨트롤러(종전 `.instance`) ──
  final NotificationBadgeController notificationBadge;
  final DeletionNoticeController deletionNotice;
  final VersionGateController versionGate;

  static AccessState _inferRoutingAccess(AppAuth auth) {
    if (auth.isGuest) return AccessState.guest;
    if (!auth.isSignedIn) return AccessState.loggedOut;
    if (auth.accountState.allowsAppUse &&
        (auth.currentRole == AppRole.student ||
            auth.currentRole == AppRole.mentor)) {
      return AccessState.full;
    }
    return AccessState.blocked;
  }
}

/// 의존성을 위젯 트리로 내려보내는 InheritedWidget.
///
/// 화면은 `AppScope.of(context)` 로 읽는다. [of] 는 의존성 등록 없이 조회만 하므로
/// `initState` 에서도 쓸 수 있다(의존성 묶음은 앱 수명 동안 바뀌지 않는다).
///
/// 조상에 [AppScope]가 없으면 모든 빌드에서 [FlutterError]를 던진다. 운영 구성은
/// 앱 루트에서만 만들며, 부분 트리와 테스트도 필요한 의존성을 명시적으로 주입한다.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final AppDependencies? dependencies = maybeOf(context);
    if (dependencies != null) return dependencies;
    throw FlutterError(
      'AppScope.of() called with a context that does not contain an AppScope. '
      'Wrap the app or test root in AppScope and provide AppDependencies explicitly.',
    );
  }

  static AppDependencies? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()?.dependencies;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      !identical(oldWidget.dependencies, dependencies);
}
