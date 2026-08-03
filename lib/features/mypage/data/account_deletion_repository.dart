import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';

/// 계정 탈퇴(P1-10) — 서버 self RPC **v2 계약**(계약 수렴)에 1:1.
///
/// ★ raw `account_deletion_request(p_user_id,…)` 는 호출자–p_user_id 일치 검사가 없어
///   service_role 전용으로 유지된다(타인 job 조작 방지). 앱은 사용자 ID 를 서버가
///   auth.uid() 로만 도출하는 **self RPC** 를 호출한다 — p_user_id 전송 없음.
///   구 self RPC 2종(account_deletion_request_self / _consented)은 앱 권한이
///   REVOKE 됐고 v2 로 대체됐다. v2 는 **파라미터가 없다**(취소창 30분은 서버
///   고정 — p_cancelable_minutes/p_dry_run 을 보내지 않는다):
///   - account_deletion_request_self_v2() → {ok, existing,
///     job_id, state, cancelable_until}
///     | {ok:false, code:FORFEIT_CONSENT_REQUIRED, balance_cents}
///   - account_deletion_request_self_consented_v2(
///     p_acknowledged_balance_cents) → 위와 동일 성공형
///     | {ok:false, code:FORFEIT_CONSENT_STALE, acknowledged_balance_cents,
///        current_balance_cents}   ← 운영 함수 exact 계약(코드 불변)
///   - account_deletion_cancel_self() → {ok} | {ok:false, code:NOT_FOUND|NOT_CANCELABLE|
///     CANCEL_WINDOW_PASSED}
///   - account_deletion_status_self() → {ok, exists, state, cancelable_until,
///     write_blocked, can_cancel}
/// ★ 42501/42883/PGRST202 는 정상 경로에서 나오지 않아야 하나(v2 배포됨),
///   미적용 환경 방어로 [AccountDeletionUnavailable] 분기(웹 폴백)를 유지한다.
///
/// ── 잔액 보유 계정(Build 12 실기기 FAIL — 학생/멘토 공통) ─────────────────
/// 잔액이 남은 계정에서 일반 self RPC 는 예외가 아니라 **정상 반환값**으로
/// `{ok:false, code:FORFEIT_CONSENT_REQUIRED, balance_cents}` 를 준다. 이전 구현은
/// `ok != true` 를 전부 "결과 확인 실패" [AppError] 로 뭉개서 ─ 사용자에겐 일반
/// 오류만 뜨고, job 도 안 생기고, 웹 폴백도 안 뜨는 막다른 길이 됐다.
/// 지금은 [DeletionForfeitConsentRequired] **typed result** 로 파싱해 화면이
/// 잔액 소멸 동의 UI 로 넘어간다(웹 미배포 오류로 취급하지 않는다).
/// ★ 잔액은 언제나 **서버 응답 balance_cents 정본**이다 — 앱이 지갑 테이블을
///   따로 읽거나 계산해서 만들지 않는다.

/// 탈퇴 요청 RPC 의 **정상 반환 분기** 합집합.
///
/// 세 갈래 전부 "서버가 정상적으로 판단해 돌려준 결과"다 — 예외가 아니다.
/// 예외(네트워크·42501·형식 위반)는 이 타입으로 오지 않고 그대로 throw 된다.
sealed class DeletionRequestOutcome {
  const DeletionRequestOutcome();
}

/// 서버가 탈퇴 job 을 접수함(신규 또는 기존 job 멱등 응답).
class DeletionAccepted extends DeletionRequestOutcome {
  const DeletionAccepted(this.result);

  final DeletionRequestResult result;
}

/// 잔액이 남아 있어 **소멸 동의**가 필요함(일반 RPC 의 정상 반환).
///
/// [balanceCents] 는 서버가 준 값 그대로다. 화면은 이 값을 표시하고, 동의 후
/// `p_acknowledged_balance_cents` 로 **가공 없이 그대로** 돌려보낸다.
class DeletionForfeitConsentRequired extends DeletionRequestOutcome {
  const DeletionForfeitConsentRequired({required this.balanceCents});

  final int balanceCents;
}

/// 동의한 잔액과 서버 실제 잔액이 어긋남 — 운영 코드 `FORFEIT_CONSENT_STALE`
/// (TOCTOU: 동의 화면을 띄운 사이에 지갑 잔액이 변동).
///
/// ★ fail-closed: 탈퇴는 접수되지 않았다. 화면은 성공 안내도 로그아웃도 하지
///   않고, 서버가 새 잔액(`current_balance_cents`)을 줬다면 그 값으로 동의를
///   다시 받는다. 새 잔액이 없거나 형식이 깨졌으면 [serverBalanceCents] 는
///   null 이고, 화면은 동의 단계를 폐기하고 처음부터 다시 시작한다
///   — 옛 동의 금액을 절대 재사용하지 않는다.
class DeletionBalanceMismatch extends DeletionRequestOutcome {
  const DeletionBalanceMismatch({this.serverBalanceCents});

  /// 서버가 알려준 현재 잔액(`current_balance_cents`). 없으면 null.
  final int? serverBalanceCents;
}

/// 탈퇴 요청 결과(self RPC 반환 {ok, existing, job_id, state, cancelable_until, dry_run}).
class DeletionRequestResult {
  const DeletionRequestResult({
    required this.existing,
    required this.jobId,
    required this.state,
    this.cancelableUntil,
  });

  /// true = 이미 접수된 job 이 있어 그 상태를 돌려줌(멱등 — 이중 탭/재요청 안전).
  final bool existing;
  final String jobId;

  /// pending|locked|purging|storage_purged|finalized|auth_soft_deleted|completed|canceled|failed
  final String state;

  /// 취소 가능 마감(서버 판정 정본 — 로컬 추정 금지).
  final DateTime? cancelableUntil;

  bool get isPending => state == 'pending';
}

/// 탈퇴 상태 조회 결과(self RPC).
class DeletionStatusResult {
  const DeletionStatusResult({
    required this.exists,
    this.state,
    this.cancelableUntil,
    required this.writeBlocked,
    required this.canCancel,
  });

  final bool exists;
  final String? state;
  final DateTime? cancelableUntil;
  final bool writeBlocked;

  /// 서버 판정: state=pending && 취소창 이내.
  final bool canCancel;
}

/// 탈퇴 취소 결과. 실패 코드는 서버 정본:
/// NOT_FOUND | NOT_CANCELABLE | CANCEL_WINDOW_PASSED.
class DeletionCancelResult {
  const DeletionCancelResult({required this.ok, this.code, this.state});

  final bool ok;
  final String? code;
  final String? state;

  bool get windowPassed => code == 'CANCEL_WINDOW_PASSED';
  bool get notCancelable => code == 'NOT_CANCELABLE';
  bool get notFound => code == 'NOT_FOUND';
}

/// 앱 내 탈퇴가 아직 서버에서 열리지 않음(EXECUTE 권한 없음 — 42501).
/// 화면은 이 오류에서만 웹 진행 폴백을 안내한다.
class AccountDeletionUnavailable extends AppError {
  const AccountDeletionUnavailable({super.cause})
      : super('앱에서 바로 탈퇴할 수 없어요. 웹 페이지에서 진행해 주세요.');
}

/// 탈퇴 포트 — 테스트는 손코딩 fake 주입(실 staging 계정으로 실행 금지).
abstract class AccountDeletionPort {
  /// 탈퇴 요청(실요청: dry_run=false 명시). 이미 job 이 있으면 멱등 응답.
  /// 잔액이 남아 있으면 [DeletionForfeitConsentRequired] 를 돌려준다(예외 아님).
  Future<DeletionRequestOutcome> requestDeletion();

  /// 잔액 소멸에 **적극 동의**한 뒤의 탈퇴 요청.
  ///
  /// [acknowledgedBalanceCents] 는 사용자가 실제로 동의한 금액 = 직전 서버 응답의
  /// `balance_cents` 원본이어야 한다(앱 계산값 금지). 서버 잔액과 어긋나면 서버가
  /// 거절하고 [DeletionBalanceMismatch] 로 돌아온다 — 접수되지 않는다.
  Future<DeletionRequestOutcome> requestDeletionWithForfeitConsent({
    required int acknowledgedBalanceCents,
  });

  /// pending + 취소창 이내에서만 성공. 판정은 서버가 한다(로컬 추정 금지).
  Future<DeletionCancelResult> cancelDeletion();

  /// 본인 탈퇴 상태(취소 버튼 노출 판정 정본 — can_cancel).
  Future<DeletionStatusResult> fetchStatus();
}

/// RPC 호출 포트 — Supabase 구체 호출을 숨겨 fake 테스트를 가능하게 한다
/// (실 staging 계정으로 삭제 RPC 를 실행하지 않는다).
abstract class AccountDeletionBackend {
  Future<Object?> rpc(String fn, Map<String, dynamic> params);
}

/// Supabase 백엔드.
class SupabaseAccountDeletionBackend implements AccountDeletionBackend {
  const SupabaseAccountDeletionBackend();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c;
  }

  @override
  Future<Object?> rpc(String fn, Map<String, dynamic> params) =>
      _client.rpc(fn, params: params);
}

/// Supabase 구현.
class SupabaseAccountDeletionRepository implements AccountDeletionPort {
  const SupabaseAccountDeletionRepository({
    AccountDeletionBackend? backend,
  }) : _backendOverride = backend;

  final AccountDeletionBackend? _backendOverride;

  AccountDeletionBackend get _backend =>
      _backendOverride ?? const SupabaseAccountDeletionBackend();

  @override
  Future<DeletionRequestOutcome> requestDeletion() async {
    final Object? data;
    try {
      // self RPC v2 — 사용자 ID 는 서버가 auth.uid() 로 도출(p_user_id 전송
      // 금지). ★ 파라미터 없음: 취소창(30분)은 서버 고정, dry_run 개념 폐기 —
      // p_cancelable_minutes/p_dry_run 을 보내면 함수 해석이 실패한다(PGRST202).
      data = await _backend.rpc(
        'account_deletion_request_self_v2',
        const <String, dynamic>{},
      );
    } catch (e) {
      throw _mapError(e);
    }
    return _parseRequestOutcome(data);
  }

  @override
  Future<DeletionRequestOutcome> requestDeletionWithForfeitConsent({
    required int acknowledgedBalanceCents,
  }) async {
    final Object? data;
    try {
      data = await _backend.rpc(
        'account_deletion_request_self_consented_v2',
        <String, dynamic>{
          // ★ 서버가 준 값을 그대로 되돌려준다 — 재계산·반올림·보정 금지.
          //   v2 파라미터는 이것 하나뿐(취소창은 서버 고정 30분).
          'p_acknowledged_balance_cents': acknowledgedBalanceCents,
        },
      );
    } catch (e) {
      throw _mapError(e);
    }
    return _parseRequestOutcome(data);
  }

  /// 요청 RPC 2종 공통 파서. 성공/동의필요/잔액불일치만 결과로 인정하고,
  /// 나머지(형식 위반·미지 코드)는 **성공 위장 없이** throw 한다(fail-closed).
  static DeletionRequestOutcome _parseRequestOutcome(Object? data) {
    if (data is! Map) {
      throw const AppError('탈퇴 요청 결과를 확인하지 못했어요. 다시 시도해 주세요.');
    }
    if (data['ok'] == true) {
      if (data['job_id'] is! String) {
        throw const AppError('탈퇴 요청 결과를 확인하지 못했어요. 다시 시도해 주세요.');
      }
      return DeletionAccepted(DeletionRequestResult(
        existing: (data['existing'] as bool?) ?? false,
        jobId: data['job_id'] as String,
        state: (data['state'] as String?) ?? 'pending',
        cancelableUntil: _parseTime(data['cancelable_until']),
      ));
    }

    final Object? rawCode = data['code'];
    final String code = rawCode is String ? rawCode : '';

    // ── 운영 exact 코드를 가장 먼저 처리한다(alias 휴리스틱보다 우선). ──
    if (code == kForfeitConsentRequiredCode) {
      final int? balance = _parseBalance(data, 'balance_cents');
      // 잔액을 모르면 동의 UI 를 만들 수 없다 — 금액 없는 동의는 받지 않는다.
      if (balance == null) {
        throw const AppError('남은 캐시 잔액을 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
      return DeletionForfeitConsentRequired(balanceCents: balance);
    }
    if (code == kForfeitConsentStaleCode) {
      return DeletionBalanceMismatch(serverBalanceCents: _staleBalance(data));
    }
    // 구/동등 코드로 배포된 환경 방어 — 접수로 오인하지 않게 넓게 인식만 한다.
    if (_isBalanceMismatchAlias(code)) {
      return DeletionBalanceMismatch(serverBalanceCents: _staleBalance(data));
    }
    throw const AppError('탈퇴 요청 결과를 확인하지 못했어요. 다시 시도해 주세요.');
  }

  /// 잔액 소멸 동의 요구 코드(운영 정본).
  static const String kForfeitConsentRequiredCode = 'FORFEIT_CONSENT_REQUIRED';

  /// 동의 금액이 낡음 = 서버 잔액 변동(운영 정본).
  /// 응답: {ok:false, code, acknowledged_balance_cents, current_balance_cents}
  static const String kForfeitConsentStaleCode = 'FORFEIT_CONSENT_STALE';

  /// 불일치 응답의 **새 서버 잔액**. 정본은 `current_balance_cents` 이고,
  /// `balance_cents` 는 구버전 함수 대비 하위 호환 fallback 으로만 읽는다.
  /// 둘 다 없거나 형식이 깨졌으면 null → 화면이 동의 단계를 폐기한다(fail-closed).
  /// ★ `acknowledged_balance_cents`(우리가 보낸 값)는 새 잔액이 아니므로 쓰지 않는다.
  static int? _staleBalance(Map<Object?, Object?> data) =>
      _parseBalance(data, 'current_balance_cents') ??
      _parseBalance(data, 'balance_cents');

  /// 금액 필드 하나를 읽는다. 양수만 잔액으로 인정한다 — 0·음수·비수치는
  /// '동의받을 잔액'이 아니므로 null 로 떨어뜨려 추정을 막는다.
  static int? _parseBalance(Map<Object?, Object?> data, String key) {
    final int? v = _parseCents(data[key]);
    return (v != null && v > 0) ? v : null;
  }

  /// 구/동등 불일치 코드(정본 [kForfeitConsentStaleCode] 가 아닌 배포 방어).
  /// 여기 걸리지 않는 미지 코드는 위에서 throw → fail-closed 는 동일하다.
  static bool _isBalanceMismatchAlias(String code) {
    if (code.isEmpty) return false;
    final String c = code.toUpperCase();
    final bool aboutBalance = c.contains('BALANCE') || c.contains('CONSENT');
    if (!aboutBalance) return false;
    return c.contains('MISMATCH') ||
        c.contains('CHANGED') ||
        c.contains('STALE') ||
        c.contains('CONFLICT');
  }

  /// bigint cents — JSON 은 int/num/문자열 어느 쪽으로도 올 수 있다.
  /// 소수·비수치는 금액으로 인정하지 않는다(추정 금지 → null → fail-closed).
  static int? _parseCents(Object? v) {
    if (v is int) return v;
    if (v is num) return v == v.roundToDouble() ? v.toInt() : null;
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  @override
  Future<DeletionCancelResult> cancelDeletion() async {
    final Object? data;
    try {
      data = await _backend.rpc(
        'account_deletion_cancel_self',
        const <String, dynamic>{},
      );
    } catch (e) {
      throw _mapError(e);
    }
    if (data is! Map) {
      throw const AppError('취소 결과를 확인하지 못했어요. 다시 시도해 주세요.');
    }
    return DeletionCancelResult(
      ok: data['ok'] == true,
      code: data['code'] as String?,
      state: data['state'] as String?,
    );
  }

  @override
  Future<DeletionStatusResult> fetchStatus() async {
    final Object? data;
    try {
      data = await _backend.rpc(
        'account_deletion_status_self',
        const <String, dynamic>{},
      );
    } catch (e) {
      throw _mapError(e);
    }
    if (data is! Map || data['ok'] != true) {
      throw const AppError('탈퇴 상태를 확인하지 못했어요. 다시 시도해 주세요.');
    }
    return DeletionStatusResult(
      exists: (data['exists'] as bool?) ?? false,
      state: data['state'] as String?,
      cancelableUntil: _parseTime(data['cancelable_until']),
      writeBlocked: (data['write_blocked'] as bool?) ?? false,
      canCancel: (data['can_cancel'] as bool?) ?? false,
    );
  }

  static DateTime? _parseTime(Object? v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  /// 앱 경로 미개방만 웹 폴백으로 바꾼다:
  /// - 42501 permission denied(EXECUTE 권한 없음)
  /// - 42883 undefined_function / PGRST202(스키마 캐시에 함수 없음) = RPC 미배포
  ///   — 동의 RPC 가 아직 안 올라간 환경에서 막다른 길이 되지 않게 한다.
  /// ★ 네트워크 오류·서버 오류는 여기 걸리지 않는다 — 웹 폴백으로 위장 금지.
  Object _mapError(Object e) {
    if (e is! PostgrestException) return e;
    final String code = e.code ?? '';
    if (code == '42501' || code == '42883' || code == 'PGRST202') {
      return AccountDeletionUnavailable(cause: e);
    }
    final String m = e.message.toLowerCase();
    if (m.contains('permission denied') ||
        m.contains('could not find the function')) {
      return AccountDeletionUnavailable(cause: e);
    }
    return e;
  }
}
