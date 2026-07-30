import '../../../shared/errors/app_error.dart';

/// `api_app_v1` 커뮤니티 쓰기 wrapper(F4/F5/F6) 공통 envelope 해석.
///
/// 서버 계약(앱 계약 v1.1 §3.3): 성공 `{ok:true, contract_version:1, ...}`,
/// 도메인 거부 `{ok:false, contract_version:1, code:'STABLE_CODE'}`.
/// ★ `ok` 필드가 없는 응답은 성공으로 간주하지 않는다(응답 불명확으로 분류).
/// ★ 예상 밖 예외(연결 실패·timeout·envelope 아님)는 '확정 실패'가 아니다 —
///   F4 는 같은 멱등키로 재호출(replay-first)해야 하고 그 전에 Storage 보상
///   삭제를 해서는 안 된다(§6.3 4분기 — community_post_actions.dart 참조).
class CommunityWriteEnvelope {
  const CommunityWriteEnvelope._({
    required this.ok,
    this.code,
    required this.fields,
  });

  final bool ok;

  /// ok=false 일 때의 안정 오류코드(항상 존재해야 정상 envelope).
  final String? code;

  /// envelope 원본 필드(post_id, idempotent_replay, updated_at,
  /// removed_image_refs, already_deleted 등 도메인 필드 접근용).
  final Map<String, dynamic> fields;

  /// F4 멱등 재생 성공 표시(성공 envelope 한정).
  bool get idempotentReplay => fields['idempotent_replay'] == true;

  /// 응답을 envelope 로 해석. `ok` 필드가 bool 이 아니면 null(불명확 응답).
  static CommunityWriteEnvelope? tryParse(Object? data) {
    if (data is! Map) return null;
    final Object? ok = data['ok'];
    if (ok is! bool) return null;
    final Map<String, dynamic> fields = <String, dynamic>{
      for (final MapEntry<dynamic, dynamic> e in data.entries)
        if (e.key is String) e.key as String: e.value,
    };
    final Object? code = data['code'];
    if (!ok && code is! String) return null; // ok:false 인데 code 없음 — 비정상.
    return CommunityWriteEnvelope._(
      ok: ok,
      code: ok ? null : code as String,
      fields: fields,
    );
  }
}

/// 커뮤니티 쓰기(F4/F5/F6) 안정 오류코드 → 사용자용 한글 문구.
/// (앱 계약 §6.4 — `ROLE_NOT_MENTOR` 와 `MENTOR_NOT_APPROVED` 는 구분 문구.)
/// 미지 코드는 null → 호출부가 일반 문구(friendlyError)로 폴백.
String? communityWriteErrorMessage(String code) {
  switch (code) {
    case 'AUTH_REQUIRED':
      return '로그인이 필요해요.';
    case 'ROLE_NOT_MENTOR':
      return '커뮤니티 글 작성·수정은 멘토만 할 수 있어요.';
    case 'MENTOR_NOT_APPROVED':
      return '멘토 승인이 완료된 뒤에 글을 작성할 수 있어요.';
    case 'ACCOUNT_BANNED':
    case 'ACCOUNT_SUSPENDED':
      return '계정 이용이 제한된 상태예요. 자세한 내용은 문의해 주세요.';
    case 'ACCOUNT_DELETION_IN_PROGRESS':
      return '탈퇴 처리 중인 계정이라 이용할 수 없어요.';
    case 'TITLE_REQUIRED':
      return '제목을 입력해 주세요.';
    case 'BODY_TOO_SHORT':
      return '내용을 10자 이상 입력해 주세요.';
    case 'CATEGORY_INVALID':
      return '카테고리를 다시 선택해 주세요.';
    case 'IMAGE_COUNT_EXCEEDED':
      return '이미지는 최대 5장까지 첨부할 수 있어요.';
    case 'IMAGE_REF_INVALID':
    case 'IMAGE_NOT_OWNED':
    case 'IMAGE_OBJECT_NOT_FOUND':
      return '이미지 첨부를 확인하지 못했어요. 이미지를 다시 첨부해 주세요.';
    case 'IMAGE_MIME_NOT_ALLOWED':
      return 'JPG·PNG·WebP·GIF 이미지만 첨부할 수 있어요.';
    case 'IMAGE_SIZE_EXCEEDED':
      return '이미지 한 장은 5MB 이하만 첨부할 수 있어요.';
    case 'POST_NOT_FOUND_OR_NOT_OWNED':
      return '글을 찾을 수 없거나 내 글이 아니에요. 새로고침 후 다시 확인해 주세요.';
    case 'UPDATE_CONFLICT':
      return '글이 다른 곳에서 먼저 수정됐어요. 최신 내용을 확인한 뒤 다시 수정해 주세요.';
  }
  return null;
}

/// 확정 도메인 거부(ok:false envelope)를 나타내는 구조화 오류.
/// [code] 는 앱 계약 §6.4 안정 코드 — 분기(예: UPDATE_CONFLICT)에 사용한다.
class CommunityWriteRejected extends AppError {
  CommunityWriteRejected(this.code)
      : super(communityWriteErrorMessage(code) ??
            '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.');

  final String code;
}
