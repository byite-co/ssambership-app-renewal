import '../../design/widgets/status_pill.dart';

/// 구독 상태 표시(라벨 + 시맨틱 톤). 웹 정본(subscriptionStatusDisplayLabel/Tone)과 동일 어휘.
class SubscriptionStatusDisplay {
  const SubscriptionStatusDisplay(this.label, this.tone);
  final String label;
  final StatusTone tone;
}

/// 구독 status(raw 문자열) → 한글 라벨 + 톤으로 세분화.
///
/// 정본 상태값: active / past_due / canceled(cancelled) / expired / pending / refunded /
/// cancel_scheduled. ★ 표시만 세분화(결제·DB 변경 없음). status 가 없거나(미상) 인식 불가면
/// [isActive] 로 폴백해 기존 2분기(구독 중/구독 만료)를 유지한다(영문 코드 노출 금지).
SubscriptionStatusDisplay subscriptionStatusDisplay(
  String? status, {
  required bool isActive,
}) {
  switch (status?.trim().toLowerCase() ?? '') {
    case 'active':
      return const SubscriptionStatusDisplay('이용 중', StatusTone.success);
    case 'cancel_scheduled':
      return const SubscriptionStatusDisplay('구독 만료 예정', StatusTone.warning);
    case 'past_due':
      return const SubscriptionStatusDisplay('결제 확인 필요', StatusTone.danger);
    case 'expired':
      return const SubscriptionStatusDisplay(
          '만료됨 · 재구독 가능', StatusTone.neutral);
    case 'canceled':
    case 'cancelled':
      return const SubscriptionStatusDisplay('해지됨', StatusTone.neutral);
    case 'refunded':
      return const SubscriptionStatusDisplay('환불됨', StatusTone.neutral);
    case 'pending':
      return const SubscriptionStatusDisplay('대기 중', StatusTone.info);
    default:
      // 미상/빈 값 → 활성 여부로 폴백(기존 동작 유지).
      return isActive
          ? const SubscriptionStatusDisplay('구독 중', StatusTone.success)
          : const SubscriptionStatusDisplay('구독 만료', StatusTone.warning);
  }
}
