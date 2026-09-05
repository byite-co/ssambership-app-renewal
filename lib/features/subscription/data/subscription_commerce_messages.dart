/// 구독 결제·해지·환불 래퍼 오류 코드 → 사용자 문구 — 웹 사전
/// (`lib/subscribe/subscribeCheckoutService.ts` `mapConfirmSubscriptionError` 등)과
/// 같은 문구를 쓴다. 지시서가 따로 정한 코드(`CASH_INSUFFICIENT`·`MENTOR_CAP_EXCEEDED`)는
/// 지시서 문구. **어느 문구에도 충전 유도가 없다**(A-4b 원칙 4).
///
/// 코드·DB명·UUID 는 화면에 내보내지 않는다.
library;

import '../../mentor_console/data/api_web_v1_envelope.dart'
    show apiWebV1CommonMessage;
import '../../mentors/format/mentor_price_format.dart';

/// `subscribe_with_cash` 실패 코드 → 문구.
String subscribeMessageForCode(String code, Map<String, dynamic> body) {
  switch (code) {
    case 'CASH_INSUFFICIENT':
      final int? shortfall = _int(body['shortfall_cents']);
      if (shortfall != null && shortfall > 0) {
        return '잔액이 ${formatWon(shortfall ~/ 100)} 부족해요';
      }
      return '잔액이 부족해요';
    case 'MENTOR_CAP_EXCEEDED':
      return '정원이 찼어요';
    case 'ALREADY_SUBSCRIBED':
      return '이미 구독 중인 멘토예요';
    case 'MENTOR_PAUSED':
      return '이 멘토는 현재 일시 휴식 중입니다. 복귀 후 다시 구독해 주세요.';
    case 'MENTOR_TERMINATED':
      return '활동을 종료한 멘토라 구독할 수 없어요';
    case 'BLOCKED':
      return '차단 상태에서는 구독할 수 없어요';
    case 'MENTOR_NOT_OPEN_FOR_SUBSCRIPTIONS':
      return '이 멘토는 현재 신규 구독을 받지 않고 있어요.';
    case 'MENTOR_NOT_APPROVED':
      return '이 멘토는 아직 승인 전이라 구독할 수 없어요.';
    case 'MENTOR_NOT_FOUND':
      return '멘토 정보를 찾을 수 없어요. 잠시 후 다시 시도해 주세요.';
    case 'ROLE_NOT_STUDENT':
      return '학생 계정에서만 구독할 수 있어요.';
    case 'ACCOUNT_BANNED':
    case 'ACCOUNT_SUSPENDED':
    case 'ACCOUNT_NOT_ACTIVE':
      return '현재 계정 상태에서는 구독을 진행할 수 없어요.';
    case 'ACCOUNT_DELETION_IN_PROGRESS':
      return '탈퇴 처리 중에는 구독할 수 없어요.';
    case 'PLAN_TIER_INVALID':
    case 'PLAN_NOT_FOUND':
    case 'PLAN_INACTIVE':
    case 'PLAN_AMOUNT_INVALID':
    case 'PLAN_MENTOR_MISMATCH':
      return '요금제 정보를 확인할 수 없어요. 잠시 후 다시 시도해 주세요.';
    case 'PLAN_AMOUNT_CHANGED':
      return '결제 화면의 금액과 현재 요금제 금액이 달라 결제를 진행하지 않았어요. '
          '캐시는 차감되지 않았습니다. 새로고침 후 금액을 확인하고 다시 시도해 주세요.';
    case 'IDEMPOTENCY_KEY_INVALID':
    case 'IDEMPOTENCY_KEY_CONFLICT':
      return '이전 결제 요청과 겹쳤어요. 화면을 다시 열고 시도해 주세요.';
    case 'ROOM_ENSURE_FAILED':
      return '질문방 연결에 실패해 결제를 확정하지 않았어요. 캐시는 차감되지 않았습니다. '
          '잠시 후 다시 시도해 주세요.';
    case 'PAYMENT_NOT_FOUND':
      return '결제 정보를 찾을 수 없어요. 잠시 후 다시 시도해 주세요.';
    case 'PAYMENT_PROCESSING':
      return '결제가 아직 처리 중이에요. 잠시 후 다시 시도해 주세요.';
    case 'PAYMENT_NOT_PENDING':
    case 'PAYMENT_STATE_UNEXPECTED':
    case 'PAYMENT_KIND_INVALID':
      return '이미 처리되었거나 진행할 수 없는 결제예요. 결제 내역을 확인해 주세요.';
    case 'PAYMENT_STALE':
      return '결제 확정 시간이 지났어요. 다시 결제해 주세요.';
    case 'ROOM_REF_MISMATCH':
    case 'SUBSCRIPTION_REF_INVALID':
    case 'PLAN_BINDING_MISMATCH':
    case 'PARTY_BINDING_MISMATCH':
    case 'LEDGER_BINDING_MISMATCH':
    case 'LEDGER_AMOUNT_MISMATCH':
    case 'LEDGER_FIELD_MISMATCH':
    case 'SUCCEEDED_NO_SUBSCRIPTION':
    case 'SUCCEEDED_NO_LEDGER':
    case 'FINANCIAL_WRITE_ERROR':
      return '결제 원장 정합성 확인이 필요해요. 고객센터로 문의해 주세요.';
  }
  return apiWebV1CommonMessage(code) ?? '구독 확정에 실패했어요. 잠시 후 다시 시도해 주세요.';
}

/// `subscription_cancel_at_period_end` / `subscription_cancel_undo` 실패 코드 → 문구.
String cancelScheduleMessageForCode(String code, Map<String, dynamic> body) {
  switch (code) {
    case 'SUBSCRIPTION_NOT_FOUND':
    case 'NOT_SUBSCRIPTION_OWNER':
      return '구독 정보를 찾을 수 없어요. 화면을 새로고침해 주세요.';
    case 'SUBSCRIPTION_NOT_CURRENT':
      return '진행 중인 구독만 해지 예약을 바꿀 수 있어요.';
    case 'ROLE_NOT_STUDENT':
      return '학생 계정에서만 쓸 수 있는 기능이에요.';
  }
  return apiWebV1CommonMessage(code) ?? '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

/// `refund_estimate` / `refund_request_create` 실패 코드 → 문구.
String refundMessageForCode(String code, Map<String, dynamic> body) {
  switch (code) {
    case 'REASON_TOO_SHORT':
      return '환불 신청 사유를 5자 이상 입력해 주세요.';
    case 'REASON_TOO_LONG':
      return '환불 사유는 2000자까지 입력할 수 있어요.';
    case 'ALREADY_REQUESTED':
      return '이미 신청한 환불이 있어요';
    case 'REFUND_NOT_AVAILABLE':
      return '기준상 환불을 신청할 수 없는 구독이에요.';
    case 'SUBSCRIPTION_NOT_CURRENT':
      return '진행 중인 구독만 환불을 신청할 수 있어요.';
    case 'SUBSCRIPTION_NOT_FOUND':
    case 'NOT_SUBSCRIPTION_OWNER':
      return '구독 정보를 찾을 수 없어요. 화면을 새로고침해 주세요.';
    case 'ROLE_NOT_STUDENT':
      return '학생 계정에서만 쓸 수 있는 기능이에요.';
    case 'ACCOUNT_BANNED':
    case 'ACCOUNT_SUSPENDED':
    case 'ACCOUNT_NOT_ACTIVE':
      return '현재 계정 상태에서는 환불을 신청할 수 없어요.';
    case 'ACCOUNT_DELETION_IN_PROGRESS':
      return '탈퇴 처리 중에는 환불을 신청할 수 없어요.';
  }
  return apiWebV1CommonMessage(code) ?? '환불 신청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.';
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}
