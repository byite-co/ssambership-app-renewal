import '../../../shared/errors/app_error.dart';

/// `api_web_v1` self 쓰기 RPC 봉투 규약 — `{ok, contract_version:1, …}` /
/// `{ok:false, contract_version:1, code, …}`.
///
/// ★ A-4a 결정(오너 2026-09-05): 앱이 `api_web_v1` 쓰기 RPC(F7·F8·F13)를 직접
///   호출한다. 판정·검증은 전부 DB 가 정본이고 앱은 봉투를 strict 로 읽는다 —
///   계약 밖 응답을 성공으로 처리하지 않는다(fail-closed).
class ApiEnvelope {
  const ApiEnvelope._(this.ok, this.code, this.body);

  final bool ok;

  /// 실패 코드(UPPER_SNAKE). 성공이면 null.
  final String? code;

  /// 봉투 전체(보조 필드 접근용 — tier·min/max 등).
  final Map<String, dynamic> body;

  /// 응답 → 봉투. 봉투 형태가 아니면 [ApiEnvelopeError] (계약 위반).
  static ApiEnvelope parse(Object? data) {
    if (data is! Map) throw const ApiEnvelopeError.malformed();
    final Map<String, dynamic> body = Map<String, dynamic>.from(data);
    if (body['contract_version'] != 1) throw const ApiEnvelopeError.malformed();
    final Object? ok = body['ok'];
    if (ok == true) return ApiEnvelope._(true, null, body);
    if (ok == false) {
      final Object? code = body['code'];
      return ApiEnvelope._(
        false,
        code is String && code.trim().isNotEmpty ? code.trim() : 'UNKNOWN',
        body,
      );
    }
    throw const ApiEnvelopeError.malformed();
  }

  /// 실패 봉투를 [ApiEnvelopeFailure] 로 던진다(성공이면 자기 자신 반환).
  ApiEnvelope requireOk(String Function(String code, Map<String, dynamic> body)
      messageForCode) {
    if (ok) return this;
    throw ApiEnvelopeFailure(code!, messageForCode(code!, body), body);
  }

  int? intField(String key) {
    final Object? v = body[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  String? stringField(String key) {
    final Object? v = body[key];
    return v is String ? v : null;
  }
}

/// 봉투 자체가 계약과 다를 때(응답이 Map 이 아니거나 contract_version 불일치).
class ApiEnvelopeError extends AppError {
  const ApiEnvelopeError.malformed()
      : super('저장 결과를 확인하지 못했어요. 다시 시도해 주세요.');
}

/// 서버가 정상 봉투로 돌려준 실패(`ok:false`). [code] 는 화면에 노출하지 않고
/// [userMessage] 만 보여준다.
class ApiEnvelopeFailure extends AppError {
  const ApiEnvelopeFailure(this.code, String userMessage, this.body)
      : super(userMessage);

  final String code;
  final Map<String, dynamic> body;
}

/// 계정·역할 공통 코드 → 문구(F7·F8·F13 공통 게이트). 모르면 null.
String? apiWebV1CommonMessage(String code) {
  switch (code) {
    case 'AUTH_REQUIRED':
      return '로그인 정보가 만료됐어요. 다시 로그인해 주세요.';
    case 'ROLE_NOT_MENTOR':
      return '멘토 계정에서만 쓸 수 있는 기능이에요.';
    case 'ACCOUNT_BANNED':
    case 'ACCOUNT_SUSPENDED':
      return '계정 이용이 제한된 상태예요. 자세한 내용은 문의해 주세요.';
    case 'ACCOUNT_DELETION_IN_PROGRESS':
      return '탈퇴 처리 중에는 이 정보를 바꿀 수 없어요.';
    case 'MENTOR_PROFILE_NOT_FOUND':
      return '멘토 프로필을 찾을 수 없어요. 고객센터로 문의해 주세요.';
    case 'MENTOR_NOT_APPROVED':
      return '멘토 승인이 완료된 뒤에 할 수 있어요.';
  }
  return null;
}
