import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../core/auth/app_auth.dart';
import '../core/auth/auth_service.dart';
import '../core/auth/deletion_notice_controller.dart';
import '../core/entitlement/subscription_summary_port.dart';
import '../core/supabase/supabase_client.dart';
import '../core/version_gate/version_gate_controller.dart';
import '../features/mypage/data/mypage_repository.dart';
import '../features/notifications/data/notification_badge_controller.dart';
import '../features/question_room/data/mentor_lookup_repository.dart';
import '../features/question_room/data/question_room_read_repository.dart';
import '../features/question_room/data/question_room_write_repository.dart';
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
    SupabaseClient? Function()? supabaseClient,
    this.questionRoomRead = const QuestionRoomReadRepository(),
    this.questionRoomWrite = const QuestionRoomWriteRepository(),
    this.mentorLookup = const MentorLookupRepository(),
    this.studentLookup = const StudentLookupRepository(),
    this.subscriptions = const SupabaseSubscriptionSummaryPort(),
    this.myPage = const MyPageRepository(),
    NotificationBadgeController? notificationBadge,
    DeletionNoticeController? deletionNotice,
    VersionGateController? versionGate,
  })  : _supabaseClient = supabaseClient ?? _productionClient,
        notificationBadge =
            notificationBadge ?? NotificationBadgeController.instance,
        deletionNotice = deletionNotice ?? DeletionNoticeController.instance,
        versionGate = versionGate ?? VersionGateController.instance;

  /// 운영 구성 — main() 이 부팅한 싱글턴들을 그대로 담는다.
  factory AppDependencies.production() =>
      AppDependencies(auth: AuthService.instance);

  static SupabaseClient? _productionClient() => SupabaseInit.clientOrNull;

  /// 인증·역할 상태(종전 `AuthService.instance`).
  final AppAuth auth;

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

  // ── 앱 전역 컨트롤러(종전 `.instance`) ──
  final NotificationBadgeController notificationBadge;
  final DeletionNoticeController deletionNotice;
  final VersionGateController versionGate;
}

/// 의존성을 위젯 트리로 내려보내는 InheritedWidget.
///
/// 화면은 `AppScope.of(context)` 로 읽는다. [of] 는 의존성 등록 없이 조회만 하므로
/// `initState` 에서도 쓸 수 있다(의존성 묶음은 앱 수명 동안 바뀌지 않는다).
///
/// ★ 폴백: 조상에 AppScope 가 없으면 운영 구성([AppDependencies.production])을 돌려준다.
///   기존 위젯 테스트(AppScope 없이 화면을 직접 pump)와 부분 트리가 종전과 동일하게
///   동작하도록 둔 것이다 — A-3(라우팅 교체)에서 진입점이 전부 AppScope 아래로 들어오면
///   이 폴백은 제거 대상이다.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  static AppDependencies? _fallback;

  static AppDependencies of(BuildContext context) =>
      maybeOf(context) ?? (_fallback ??= AppDependencies.production());

  static AppDependencies? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()?.dependencies;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      !identical(oldWidget.dependencies, dependencies);
}
