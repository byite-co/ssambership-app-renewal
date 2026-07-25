import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../deeplink/deep_link_service.dart';
import '../entitlement/entitlement.dart';
import '../push/push_service.dart';
import '../supabase/supabase_client.dart';
import '../web_bridge/web_session_hygiene.dart';
import 'account_status.dart';
import 'deletion_notice_controller.dart';

/// 사용자 역할. 화면에는 영문 코드 대신 의미에 맞는 한글 UI를 쓴다.
enum AppRole { student, mentor, admin, guest }

/// 앱 접근 상태 — 진입 분기(entry_guard)의 단일 소스.
/// - loading: 부팅 중(세션 복원/프로필 로드)
/// - loggedOut: 세션 없음 + 게스트 아님 → 로그인 화면
/// - guest: 둘러보기(로그인 없이 제한 입장)
/// - full: 로그인 + 계정 이용가능(active|deletionPending) + role student|mentor → 앱 전체
/// - blocked: 로그인 + (banned|suspended|탈퇴 진행·완료|조회 실패) 또는 role admin → 차단 화면
///   (조회 실패는 재시도 가능 차단 — isRecoverableBlock 참고)
enum AccessState { loading, loggedOut, guest, full, blocked }

/// 인증 서비스 = 세션 + 프로필(role·계정상태·구독) 오케스트레이션.
///
/// ChangeNotifier 로 두어 GoRouter refreshListenable 로 진입 분기를 갱신한다.
/// - 세션: Supabase 이메일+비밀번호 로그인 / 로그아웃 / 앱 재시작 시 복원·유지.
/// - 프로필: 로그인 후 users.role, users.status(account_status), subscriptions(entitlement) read.
class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  bool _bootstrapping = true;
  bool _guest = false;
  AppRole _role = AppRole.guest;
  bool _roleFetchFailed = false;
  String _displayName = '';
  AccountState _account = AccountState.fetchFailed;
  Entitlement _entitlement = Entitlement.none;
  StreamSubscription<AuthState>? _authSub;

  // ── 외부 노출 게터 ──
  bool get isBootstrapping => _bootstrapping;
  bool get isGuest => _guest;
  AppRole get currentRole => _role;
  AccountState get accountState => _account;
  Entitlement get entitlement => _entitlement;

  /// 화면 표시용 이름(nickname 우선, 없으면 full_name, 둘 다 없으면 빈 문자열).
  /// 하드코딩하지 않는다 — users 프로필에 없으면 빈 값.
  String get displayName => _displayName;

  /// 역할 표시용 한글 라벨(영문 코드 노출 금지). 학생·멘토 외에는 빈 문자열.
  String get roleLabel {
    switch (_role) {
      case AppRole.student:
        return '학생';
      case AppRole.mentor:
        return '멘토';
      case AppRole.admin:
      case AppRole.guest:
        return '';
    }
  }

  SupabaseClient? get _client => SupabaseInit.clientOrNull;
  Session? get _session => _client?.auth.currentSession;

  /// 현재 로그인 여부(실제 Supabase 세션 기준).
  bool get isSignedIn => _session != null;

  /// 진입 분기용 단일 상태.
  AccessState get access => computeAccess(
        bootstrapping: _bootstrapping,
        signedIn: isSignedIn,
        guest: _guest,
        role: _role,
        roleFetchFailed: _roleFetchFailed,
        account: _account,
      );

  /// 진입 분기 순수 판정(단위 테스트 진입점) — fail-closed.
  ///
  /// - 조회 실패(계정 상태 fetchFailed·role 조회 실패)는 절대 full 로 통과시키지
  ///   않는다. 단, 영구 차단이 아니라 '재시도 가능한 차단'이다(computeRecoverableBlock).
  /// - deletionPending 은 서버가 쓰기를 막지 않는 취소 가능 창 → 이용 허용.
  /// - deletionLocked/deleted 는 비복구 차단(재시도 버튼 비노출).
  @visibleForTesting
  static AccessState computeAccess({
    required bool bootstrapping,
    required bool signedIn,
    required bool guest,
    required AppRole role,
    required bool roleFetchFailed,
    required AccountState account,
  }) {
    if (bootstrapping) return AccessState.loading;
    if (signedIn) {
      // 조회 실패(상태·role) → 차단(재시도 가능). active 로 통과 금지.
      if (account.isRetryable || roleFetchFailed) return AccessState.blocked;
      // 계정 차단(banned/suspended/탈퇴 진행·완료) → 차단.
      if (!account.allowsAppUse) return AccessState.blocked;
      // 관리자 계정은 이 앱(학생·멘토용)에서 차단.
      if (role == AppRole.admin) return AccessState.blocked;
      if (role == AppRole.student || role == AppRole.mentor) {
        return AccessState.full;
      }
      // role 불명(트리거 미생성 등) → 보수적으로 차단.
      return AccessState.blocked;
    }
    if (guest) return AccessState.guest;
    return AccessState.loggedOut;
  }

  /// 차단 화면에 보여줄 안내 문구(상태별 구분 문구).
  String get blockedMessage {
    // 계정 상태 자체의 차단/실패 문구가 있으면 그것이 최우선.
    final String accountMessage = _account.blockedMessage;
    if (accountMessage.isNotEmpty) return accountMessage;
    if (isSignedIn && _roleFetchFailed) {
      return '프로필을 불러오지 못했어요.\n네트워크 연결을 확인한 뒤 다시 시도해 주세요.';
    }
    if (isSignedIn && _role == AppRole.admin) {
      return '이 앱은 학생·멘토 전용이에요.\n관리자 기능은 웹 콘솔에서 이용해 주세요.';
    }
    // role 불명(행에 역할 없음 등) — 재시도로 안 풀리는 케이스 안내.
    return '계정 정보를 확인할 수 없어요.\n문제가 계속되면 고객센터에 문의해 주세요.';
  }

  /// 차단 사유가 '일시 조회 실패'(재시도로 풀릴 수 있는 경우)인지.
  bool get isRecoverableBlock => computeRecoverableBlock(
        signedIn: isSignedIn,
        role: _role,
        roleFetchFailed: _roleFetchFailed,
        account: _account,
      );

  /// 재시도 가능 차단 판정(단위 테스트 진입점).
  /// deletionLocked/deleted/banned 은 재시도로 풀리지 않으므로 false.
  @visibleForTesting
  static bool computeRecoverableBlock({
    required bool signedIn,
    required AppRole role,
    required bool roleFetchFailed,
    required AccountState account,
  }) =>
      signedIn &&
      role != AppRole.admin &&
      (account.isRetryable || roleFetchFailed);

  /// main() 에서 1회 호출. 세션 복원 + 프로필 로드 + auth 변화 구독.
  Future<void> bootstrap() async {
    final SupabaseClient? client = _client;
    if (client == null) {
      // Supabase 미초기화(키 없음) — 로그인 불가. 게스트/로그아웃 흐름만 동작.
      _bootstrapping = false;
      notifyListeners();
      return;
    }
    _authSub ??= client.auth.onAuthStateChange.listen(_onAuthChange);
    await _loadProfile();
    _bootstrapping = false;
    notifyListeners();
  }

  void _onAuthChange(AuthState data) {
    if (data.event == AuthChangeEvent.signedOut) {
      // 푸시/딥링크 상태 정리(철회 자체는 signOut() 이 세션 유효 시점에 이미 수행).
      PushService.instance.onSignedOut();
      DeepLinkService.instance.onSignedOut();
      // WebView 쿠키 정리 — 계정 전환 시 이전 사용자 웹 세션 재사용 차단(no-op 안전).
      unawaited(WebSessionHygiene.clear());
      _resetProfile();
      notifyListeners();
      return;
    }
    if (data.event == AuthChangeEvent.signedIn ||
        data.event == AuthChangeEvent.initialSession) {
      final String? userId = data.session?.user.id;
      if (userId != null) {
        // 토큰 등록(서버가 재소유 처리 — 계정 전환도 재등록만으로 안전) +
        // 로그인 대기 딥링크 1회 실행. 실패해도 인증 흐름은 막지 않는다.
        unawaited(PushService.instance.onSignedIn(userId));
        DeepLinkService.instance.onSignedIn(userId);
      }
    }
    // signedIn / tokenRefreshed / initialSession / userUpdated 등 → 프로필 재로드.
    unawaited(_loadProfile().then((_) => notifyListeners()));
  }

  Future<void> _loadProfile() async {
    final SupabaseClient? client = _client;
    final Session? session = _session;
    if (client == null || session == null) {
      _resetProfile();
      return;
    }
    final String userId = session.user.id;
    // role 조회 '실패'(네트워크 등)는 '역할 없음(guest)'과 구분해 재시도 가능 차단으로.
    final AppRole? role = await _readRole(client, userId);
    _roleFetchFailed = role == null;
    _role = role ?? AppRole.guest;
    _displayName = await _readDisplayName(client, userId);
    _account = await AccountStatusReader.fetch(client, userId);
    if (_role == AppRole.student) {
      _entitlement = await EntitlementReader.fetchForStudent(client, userId);
    } else {
      _entitlement = Entitlement.none;
    }
  }

  void _resetProfile() {
    _role = AppRole.guest;
    _roleFetchFailed = false;
    _displayName = '';
    _account = AccountState.fetchFailed;
    _entitlement = Entitlement.none;
  }

  /// role read. 값 없음 → guest(비복구 차단), 조회 실패 → null(재시도 가능 차단).
  Future<AppRole?> _readRole(SupabaseClient client, String userId) async {
    try {
      final Map<String, dynamic>? row = await client
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      switch ((row?['role'] as String?)?.trim()) {
        case 'student':
          return AppRole.student;
        case 'mentor':
          return AppRole.mentor;
        case 'admin':
          return AppRole.admin;
        default:
          return AppRole.guest;
      }
    } catch (_) {
      return null;
    }
  }

  /// 표시용 이름 read(RLS: 본인 행만). nickname 우선, 없으면 full_name, 둘 다 없으면 ''.
  Future<String> _readDisplayName(SupabaseClient client, String userId) async {
    try {
      final Map<String, dynamic>? row = await client
          .from('users')
          .select('nickname, full_name')
          .eq('id', userId)
          .maybeSingle();
      final String nickname = (row?['nickname'] as String?)?.trim() ?? '';
      if (nickname.isNotEmpty) return nickname;
      return (row?['full_name'] as String?)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 이메일+비밀번호 로그인. 실패 시 AuthException 전파(화면에서 안내).
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final SupabaseClient? client = _client;
    if (client == null) {
      throw const AuthException('백엔드에 연결되어 있지 않아요. 잠시 후 다시 시도해 주세요.');
    }
    _guest = false;
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    // onAuthStateChange 가 비동기로 갱신하지만, 즉시 반영 위해 한 번 더 로드.
    await _loadProfile();
    notifyListeners();
  }

  /// 둘러보기(게스트 입장).
  void enterAsGuest() {
    _guest = true;
    _resetProfile();
    notifyListeners();
  }

  /// 로그아웃. ★ 디바이스 토큰 철회는 세션이 살아 있는 signOut '이전'에 수행
  /// (철회 실패는 로그아웃을 막지 않는다 — PushService 가 내부에서 삼킨다).
  Future<void> signOut() async {
    final SupabaseClient? client = _client;
    _guest = false;
    DeepLinkService.instance.onSignedOut(); // 이전 사용자 대기 딥링크 폐기.
    // 이전 사용자의 탈퇴 예약 배너 상태 폐기 — 다음 로그인 사용자에게 새지 않게.
    // (배너 정본은 서버 self RPC 라, 비운 뒤 다음 진입에서 다시 조회한다.)
    DeletionNoticeController.instance.clear();
    // 로그아웃 '전' WebView 쿠키/세션 정리 — 다음 사용자가 재사용하지 못하게.
    await WebSessionHygiene.clear();
    await performSignOut(
      revokePushToken: PushService.instance.revokeBeforeSignOut,
      supabaseSignOut: () async {
        if (client != null) await client.auth.signOut();
      },
    );
    _resetProfile();
    notifyListeners();
  }

  /// 로그아웃 순서 보장(단위 테스트 진입점) — 철회가 반드시 signOut 보다 먼저.
  @visibleForTesting
  static Future<void> performSignOut({
    required Future<void> Function() revokePushToken,
    required Future<void> Function() supabaseSignOut,
  }) async {
    await revokePushToken();
    await supabaseSignOut();
  }

  /// 차단/상태불명 화면에서 프로필 재시도.
  Future<void> reloadProfile() async {
    await _loadProfile();
    notifyListeners();
  }
}
