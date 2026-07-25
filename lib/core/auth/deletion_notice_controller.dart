import 'package:flutter/foundation.dart';

import '../../features/mypage/data/account_deletion_repository.dart';

/// 탈퇴 예약 상시 배너(§5)의 **공통 상태 소스**.
///
/// 정본은 서버 self RPC `account_deletion_status_self()` 하나뿐이다
/// ({ok, exists, state, cancelable_until, write_blocked, can_cancel} —
/// [SupabaseAccountDeletionRepository.fetchStatus] 가 1:1 로 옮긴다).
/// - 취소 가능 여부는 서버 `can_cancel` 로만 판정한다. 로컬 시계로 취소창을
///   계산하지 않는다(클라이언트 자체 계산 금지).
/// - 로컬 캐시(SharedPreferences 등)에 배너 상태를 저장하지 않는다. 앱 재시작·
///   재로그인 후 배너는 **서버 재조회로만** 복원된다(§5-5).
/// - 조회 전·조회 실패·잡 없음은 전부 미노출(fail-closed) — '탈퇴 예약 중'이라는
///   단정을 서버 확인 없이 만들지 않는다.
///
/// 홈 셸과 마이페이지가 같은 [instance] 를 보므로 배너 상태가 두 표면에서 갈리지
/// 않고, 동시 요청은 single-flight 로 1회 RPC 에 수렴한다.
class DeletionNoticeController extends ChangeNotifier {
  DeletionNoticeController({
    this.port = const SupabaseAccountDeletionRepository(),
  });

  /// 앱 공통 인스턴스(홈 셸·마이페이지 공유).
  static final DeletionNoticeController instance = DeletionNoticeController();

  final AccountDeletionPort port;

  /// 배너를 띄우는 탈퇴 잡 상태. `completed` 는 앱 이용 자체가 끝난 상태라 제외하고,
  /// `canceled`/`failed` 는 '없던 일'이라 제외한다(account_status.dart 규칙과 동일).
  static const Set<String> _noticeStates = <String>{
    'pending',
    'locked',
    'purging',
    'storage_purged',
    'finalized',
    'auth_soft_deleted',
  };

  DeletionStatusResult? _status;
  bool _loaded = false;
  Future<void>? _inFlight;

  /// 세대 토큰 — [clear] (로그아웃·재로그인) 이후 늦게 도착한 이전 계정 응답이
  /// 배너를 되살리지 못하게 한다.
  int _generation = 0;

  DeletionStatusResult? get status => _status;

  /// 서버 응답을 한 번이라도 정상 수신했는지.
  bool get isLoaded => _loaded;

  /// 진행 중인 탈퇴 잡이 있어 배너를 띄워야 하는지(서버 정본).
  bool get showsNotice {
    final DeletionStatusResult? s = _status;
    if (s == null || !s.exists) return false;
    final String state = s.state?.trim().toLowerCase() ?? '';
    return _noticeStates.contains(state);
  }

  /// 취소 버튼 노출 — 서버 `can_cancel` 이 정본. locked/purging(write_blocked)과
  /// pending 아닌 상태에서는 서버 판정과 무관하게도 노출하지 않는다(§5-4 이중 방어).
  /// 값 부재·판정 불가는 전부 미노출(fail-closed).
  bool get canCancel {
    final DeletionStatusResult? s = _status;
    if (s == null || !s.exists) return false;
    if (!s.canCancel) return false;
    if (s.writeBlocked) return false;
    return (s.state?.trim().toLowerCase() ?? '') == 'pending';
  }

  /// 취소 가능 마감(서버 `cancelable_until`). null 이면 표시하지 않는다(추정 금지).
  DateTime? get cancelableUntil => _status?.cancelableUntil;

  /// 아직 서버 응답을 받지 못했을 때만 조회한다(화면 진입마다 중복 RPC 방지).
  Future<void> ensureLoaded() => _loaded ? Future<void>.value() : refresh();

  /// 서버 재조회. 진행 중인 요청이 있으면 그 요청을 공유한다(single-flight) —
  /// 홈·마이페이지 두 배너가 같은 시점에 요청해도 RPC 는 1회다.
  Future<void> refresh() {
    final Future<void>? running = _inFlight;
    if (running != null) return running;
    final int gen = ++_generation;
    final Future<void> next = port.fetchStatus().then((DeletionStatusResult s) {
      if (gen != _generation) return; // clear 이후 늦은 응답 폐기
      _status = s;
      _loaded = true;
    }).catchError((Object _) {
      // 조회 실패 → 마지막 정상 스냅샷 유지. 한 번도 못 받았으면 미노출(fail-closed).
    }).whenComplete(() {
      if (gen != _generation) return;
      _inFlight = null;
      notifyListeners();
    });
    _inFlight = next;
    return next;
  }

  /// 로그아웃·계정 전환 시 이전 계정의 배너 상태를 남기지 않는다.
  void clear() {
    _generation++;
    _status = null;
    _loaded = false;
    _inFlight = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++; // 진행 중 응답이 dispose 후 notifyListeners 하지 않도록.
    super.dispose();
  }
}
