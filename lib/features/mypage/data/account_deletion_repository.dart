import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';

/// 계정 탈퇴(P1-10) — 서버 self RPC 계약(SQL 161, 2026-07-21 staging 배포·검증)에 1:1.
///
/// ★ raw `account_deletion_request(p_user_id,…)` 는 호출자–p_user_id 일치 검사가 없어
///   service_role 전용으로 유지된다(타인 job 조작 방지). 앱은 사용자 ID 를 서버가
///   auth.uid() 로만 도출하는 **self RPC 3종**을 호출한다 — p_user_id 전송 없음:
///   - account_deletion_request_self(p_cancelable_minutes, p_dry_run) → {ok, existing,
///     job_id, state, cancelable_until, dry_run}
///   - account_deletion_cancel_self() → {ok} | {ok:false, code:NOT_FOUND|NOT_CANCELABLE|
///     CANCEL_WINDOW_PASSED}
///   - account_deletion_status_self() → {ok, exists, state, cancelable_until,
///     write_blocked, can_cancel}
/// ★ 실제 요청은 반드시 `p_dry_run=false` 명시 — 서버 기본값에 의존하지 않는다.
/// ★ 42501 은 이제 정상 경로에서 나오지 않아야 하나(셀프 RPC 배포됨), 미적용 환경
///   방어로 [AccountDeletionUnavailable] 분기(웹 폴백)를 유지한다.

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
  Future<DeletionRequestResult> requestDeletion();

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
    this.cancelableMinutes = 30,
    AccountDeletionBackend? backend,
  }) : _backendOverride = backend;

  /// 취소 가능 창(분) — 서버 기본과 동일 값을 명시 전달.
  final int cancelableMinutes;

  final AccountDeletionBackend? _backendOverride;

  AccountDeletionBackend get _backend =>
      _backendOverride ?? const SupabaseAccountDeletionBackend();

  @override
  Future<DeletionRequestResult> requestDeletion() async {
    final Object? data;
    try {
      // self RPC — 사용자 ID 는 서버가 auth.uid() 로 도출(p_user_id 전송 금지).
      data = await _backend.rpc(
        'account_deletion_request_self',
        <String, dynamic>{
          'p_cancelable_minutes': cancelableMinutes,
          // ★ dry_run 기본값에 의존하지 않고 실요청을 명시한다.
          'p_dry_run': false,
        },
      );
    } catch (e) {
      throw _mapError(e);
    }
    if (data is! Map || data['ok'] != true || data['job_id'] is! String) {
      throw const AppError('탈퇴 요청 결과를 확인하지 못했어요. 다시 시도해 주세요.');
    }
    return DeletionRequestResult(
      existing: (data['existing'] as bool?) ?? false,
      jobId: data['job_id'] as String,
      state: (data['state'] as String?) ?? 'pending',
      cancelableUntil: _parseTime(data['cancelable_until']),
    );
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

  /// 42501(permission denied) = 앱 경로 미개방 → 웹 폴백 안내용 typed error.
  Object _mapError(Object e) {
    if (e is PostgrestException &&
        (e.code == '42501' ||
            e.message.toLowerCase().contains('permission denied'))) {
      return AccountDeletionUnavailable(cause: e);
    }
    return e;
  }
}
