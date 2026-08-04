import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/errors/app_error.dart';
import 'models/individual_question_models.dart';

/// 개별질문(IQ) 서버 구조화 오류코드 → 사용자용 한글 문구.
///
/// 서버 계약: `iq_append_message` 등 IQ RPC 는 `raise exception 'CODE'` 형식이라
/// PostgrestException.message 가 코드로 시작한다(`NOT_ANSWERABLE_STATUS:answered`
/// 처럼 `:` 뒤 상세가 붙는 코드도 있다 — 선두 토큰만 대조한다).
/// 첨부 등록(`add_individual_question_attachment`)의 신규 실패 코드
/// (STORAGE_*·MIME_*·SIZE_EXCEEDED·ACCOUNT_*)도 여기서 함께 매핑한다.
/// 알 수 없는 코드는 null 반환 → 호출부가 기존 일반 문구로 폴백한다.
/// ★ 내부 코드·SQL·RPC명은 절대 화면에 노출하지 않는다(qna_error_mapper 규약).
String? iqErrorMessage(Object e) {
  final String? code = iqErrorCode(e);
  if (code == null) return null;
  switch (code) {
    // 입력·세션
    case 'AUTH_REQUIRED':
      return '로그인이 필요해요.';
    case 'BODY_REQUIRED':
      return '메시지 내용을 입력해 주세요.';
    // 존재·당사자
    case 'QUESTION_NOT_FOUND':
      return '질문을 찾을 수 없어요. 새로고침 후 다시 시도해 주세요.';
    case 'NOT_QUESTION_PARTY':
      return '이 질문에 대한 권한이 없어요.';
    // 계정 상태(커뮤니티·qna 매퍼와 동일 문장으로 통일)
    case 'ACCOUNT_BANNED':
    case 'ACCOUNT_SUSPENDED':
      return '계정 이용이 제한된 상태예요. 자세한 내용은 문의해 주세요.';
    case 'ACCOUNT_NOT_ACTIVE':
      return '현재 계정 상태에서는 이 기능을 사용할 수 없어요.';
    case 'ACCOUNT_DELETION_IN_PROGRESS':
      return '탈퇴 처리 중에는 이 기능을 사용할 수 없어요.';
    // 관계·상태
    case 'BLOCKED':
      return '차단 상태의 상대와는 질문을 주고받을 수 없어요.';
    case 'QUESTION_LOCKED':
      return '이미 종료된 질문이라 더 보낼 수 없어요.';
    case 'NOT_ANSWERABLE_STATUS':
      return '지금 상태에서는 진행할 수 없어요. 화면을 새로고침해 주세요.';
    case 'MENTOR_NOT_APPROVED':
      return '멘토 승인 상태가 확인되지 않아 지금은 진행할 수 없어요.';
    // 첨부 등록(계약 7 — 신규 실패 코드)
    case 'STORAGE_OBJECT_NOT_FOUND':
      return '업로드한 파일을 찾지 못했어요. 다시 첨부해 주세요.';
    case 'STORAGE_OBJECT_NOT_OWNED':
      return '첨부 파일을 등록하지 못했어요. 다시 시도해 주세요.';
    case 'MIME_MISMATCH':
    case 'MIME_NOT_ALLOWED':
      return '지원하지 않는 파일 형식이에요. 다른 파일로 다시 첨부해 주세요.';
    case 'SIZE_EXCEEDED':
      return '파일이 너무 커요. 더 작은 파일로 다시 첨부해 주세요.';
    // 메시지 연결 검증(서버 가드 — 정상 앱 흐름에서는 도달하지 않는다):
    // MESSAGE_NOT_IN_QUESTION = 다른 질문 메시지, MESSAGE_AUTHOR_MISMATCH =
    // 내가 쓰지 않은 메시지(20260804113000 가드). 스테일 화면 재시도 안내.
    case 'MESSAGE_NOT_IN_QUESTION':
    case 'MESSAGE_AUTHOR_MISMATCH':
      return '첨부를 메시지에 연결하지 못했어요. 화면을 새로고침한 뒤 다시 시도해 주세요.';
  }
  return null;
}

/// 예외에서 IQ 오류코드 토큰만 추출(대문자+밑줄, message **선두** 일치).
/// `NOT_ANSWERABLE_STATUS:answered` 는 선두 토큰 `NOT_ANSWERABLE_STATUS` 로
/// 수렴한다. PostgrestException 이 아니거나 코드 형태가 아니면 null.
String? iqErrorCode(Object e) {
  if (e is! PostgrestException) return null;
  final RegExpMatch? m =
      RegExp(r'^[A-Z][A-Z0-9_]+').firstMatch(e.message.trim());
  return m?.group(0);
}

/// 알려진 IQ 코드면 AppError(한글)로 변환, 아니면 원본 그대로 반환.
/// 호출부는 `throw mapIqError(e)` 한 줄로 처리한다(qna 매퍼와 동일 규약).
Object mapIqError(Object e) {
  final String? msg = iqErrorMessage(e);
  return msg == null ? e : AppError(msg, cause: e);
}

/// IQ 화면 공용 실패 문구 — 우선순위: AppError(이미 한글) → 구조화 코드 매핑
/// ([iqErrorMessage]) → 레거시 포함 매칭([iqFailureMessage]) 폴백.
/// 어느 경로로도 서버 원문·영문 코드는 화면에 나가지 않는다.
String iqActionFailureText(Object e) {
  if (e is AppError) return e.userMessage;
  return iqErrorMessage(e) ?? iqFailureMessage(e);
}
