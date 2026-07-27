import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/errors/app_error.dart';

/// 질문방 RPC(qna_*) 구조화 오류코드 → 사용자용 한글 문구.
///
/// 서버 계약(docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md §1): qna_* 함수는
/// `raise exception 'CODE'` 형식이라 PostgrestException.message 에 코드 문자열이
/// 그대로 들어온다(P0001). 알 수 없는 코드는 null 반환 → 호출부가 일반
/// 재시도 문구(friendlyError)로 폴백한다. 내부 SQL/RPC명은 절대 노출하지 않는다.
String? qnaErrorMessage(Object e) {
  final String? code = qnaErrorCode(e);
  if (code == null) return null;
  switch (code) {
    // 사용량·질문권
    case 'WEEKLY_LIMIT_EXHAUSTED':
      return '이번 주 질문 한도를 모두 사용했어요. 다음 주에 다시 질문할 수 있어요.';
    case 'FREE_QUOTA_TOTAL_EXHAUSTED':
    case 'FREE_QUOTA_MENTOR_EXHAUSTED':
      return '무료 질문권을 모두 사용했어요.';
    case 'FREE_QUOTA_EXPIRED':
      return '무료 질문 기간이 끝났어요.';
    // 구독 환불 보류
    case 'SUBSCRIPTION_REFUND_PENDING':
      return '환불 처리 중인 구독이라 지금은 이용할 수 없어요.';
    // 스레드 상태
    case 'THREAD_LOCKED':
      return '이미 종료(확인 완료)된 질문이라 더 보낼 수 없어요.';
    case 'NOT_ANSWERED':
      return '아직 답변이 도착하지 않은 질문이에요.';
    // 계정 상태
    case 'ACCOUNT_BANNED':
    case 'ACCOUNT_SUSPENDED':
      return '계정 이용이 제한된 상태예요. 자세한 내용은 문의해 주세요.';
    // 멘토 자격
    case 'MENTOR_NOT_APPROVED':
      return '멘토 승인 상태가 확인되지 않아 지금은 진행할 수 없어요.';
    // 당사자·권한
    case 'NOT_ROOM_PARTY':
    case 'STUDENT_ONLY':
    case 'MENTOR_CANNOT_CREATE_THREAD':
      return '이 질문방에서 할 수 없는 동작이에요.';
    case 'BLOCKED':
      return '차단 상태의 상대와는 질문을 주고받을 수 없어요.';
    // 첨부
    case 'STORAGE_PATH_REQUIRED':
    case 'STORAGE_PATH_MISMATCH':
    case 'STORAGE_OBJECT_NOT_OWNED':
    case 'MESSAGE_THREAD_MISMATCH':
      return '첨부 파일을 등록하지 못했어요. 다시 시도해 주세요.';
    // 존재하지 않음
    case 'THREAD_NOT_FOUND':
    case 'ROOM_NOT_FOUND':
      return '질문을 찾을 수 없어요. 새로고침 후 다시 시도해 주세요.';
    // 입력·세션(정상 흐름에선 드묾)
    case 'AUTH_REQUIRED':
      return '로그인이 필요해요.';
    case 'TITLE_REQUIRED':
      return '질문 제목이 필요해요.';
    case 'BODY_REQUIRED':
      return '메시지 내용을 입력해 주세요.';
  }
  return null;
}

/// 예외에서 qna 오류코드 토큰만 추출(대문자+밑줄). 못 찾으면 null.
String? qnaErrorCode(Object e) {
  if (e is! PostgrestException) return null;
  final RegExpMatch? m =
      RegExp(r'^[A-Z][A-Z0-9_]+$').firstMatch(e.message.trim());
  return m?.group(0);
}

/// PostgreSQL unique_violation(23505) 여부 — 첨부 storage_path UNIQUE 재시도 판정용.
bool isUniqueViolation(Object e) =>
    e is PostgrestException && e.code == '23505';

/// 알려진 qna 코드면 AppError(한글)로 변환, 아니면 원본 그대로 반환.
/// 호출부는 `throw mapQnaError(e)` 한 줄로 처리한다(원문 비노출 규약 유지).
Object mapQnaError(Object e) {
  final String? msg = qnaErrorMessage(e);
  return msg == null ? e : AppError(msg, cause: e);
}
