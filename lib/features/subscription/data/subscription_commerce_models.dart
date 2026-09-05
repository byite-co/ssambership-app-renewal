/// 구독 결제·해지·환불 래퍼(`api_app_v1`, DB-4 199·200) 반환 모델.
///
/// 숫자·날짜는 RPC 반환값만 쓴다(날조 금지). cents = 원 × 100.
library;

DateTime? _time(Object? v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return fallback;
}

/// `subscribe_with_cash` 성공 봉투.
class SubscribeSuccess {
  const SubscribeSuccess({
    required this.subscriptionId,
    required this.roomId,
    required this.planTier,
    required this.debitedCents,
    required this.balanceAfterCents,
    this.idempotent = false,
    this.reactivated = false,
    this.currentPeriodEnd,
    this.nextBillingAt,
  });

  final String subscriptionId;

  /// 정본 F12 가 확보한 질문방 — 성공 직후 이 방으로 이동한다.
  final String roomId;
  final String planTier;
  final int debitedCents;
  final int balanceAfterCents;

  /// 같은 멱등 키의 첫 결과 재생이면 true(차감 0).
  final bool idempotent;
  final bool reactivated;
  final DateTime? currentPeriodEnd;
  final DateTime? nextBillingAt;

  factory SubscribeSuccess.fromBody(Map<String, dynamic> b) {
    return SubscribeSuccess(
      subscriptionId: '${b['subscription_id'] ?? ''}',
      roomId: '${b['room_id'] ?? ''}',
      planTier: '${b['plan_tier'] ?? ''}',
      debitedCents: _int(b['debited_cents']),
      balanceAfterCents: _int(b['balance_after_cents']),
      idempotent: b['idempotent'] == true,
      reactivated: b['reactivated'] == true,
      currentPeriodEnd: _time(b['current_period_end']),
      nextBillingAt: _time(b['next_billing_at']),
    );
  }
}

/// `subscription_cancel_at_period_end` / `subscription_cancel_undo` 성공 봉투.
class CancelScheduleResult {
  const CancelScheduleResult({
    required this.subscriptionId,
    required this.cancelAtPeriodEnd,
    this.alreadyScheduled = false,
    this.wasScheduled = false,
    this.currentPeriodEnd,
    this.nextBillingAt,
  });

  final String subscriptionId;
  final bool cancelAtPeriodEnd;
  final bool alreadyScheduled;
  final bool wasScheduled;
  final DateTime? currentPeriodEnd;
  final DateTime? nextBillingAt;

  factory CancelScheduleResult.fromBody(Map<String, dynamic> b) {
    return CancelScheduleResult(
      subscriptionId: '${b['subscription_id'] ?? ''}',
      cancelAtPeriodEnd: b['cancel_at_period_end'] == true,
      alreadyScheduled: b['already_scheduled'] == true,
      wasScheduled: b['was_scheduled'] == true,
      currentPeriodEnd: _time(b['current_period_end']),
      nextBillingAt: _time(b['next_billing_at']),
    );
  }
}

/// `refund_estimate` 성공 봉투 — 예상액과 근거 규칙(웹 TS 정본과 8/8 일치 실측).
class RefundEstimate {
  const RefundEstimate({
    required this.refundableCents,
    required this.amountCents,
    required this.rule,
    required this.bracketReason,
    this.usageStarted = false,
    this.elapsedDays = 0,
    this.periodDays = 0,
    this.remainingDays = 0,
    this.periodStart,
    this.periodEnd,
  });

  final int refundableCents;
  final int amountCents;

  /// 서버 규칙 문구 그대로 — '이용 개시 전' · '1/3 전' · '1/2 전' · '1/2 후' · '계산 불가'.
  final String rule;

  /// 서버 판정 코드 — before_usage · lt_1_3 · lt_1_2 · ge_1_2 · invalid(화면 미노출).
  final String bracketReason;
  final bool usageStarted;
  final int elapsedDays;
  final int periodDays;
  final int remainingDays;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// 기준상 환불액 0원(신청은 가능하되 경고).
  bool get isZero => refundableCents <= 0;

  /// 결제액 − 환불 예정액(‘이미 쓴 N일치’ 줄).
  int get deductedCents => amountCents - refundableCents;

  factory RefundEstimate.fromBody(Map<String, dynamic> b) {
    return RefundEstimate(
      refundableCents: _int(b['refundable_cents']),
      amountCents: _int(b['amount_cents']),
      rule: '${b['rule'] ?? ''}',
      bracketReason: '${b['bracket_reason'] ?? ''}',
      usageStarted: b['usage_started'] == true,
      elapsedDays: _int(b['elapsed_days']),
      periodDays: _int(b['period_days']),
      remainingDays: _int(b['remaining_days']),
      periodStart: _time(b['period_start']),
      periodEnd: _time(b['period_end']),
    );
  }
}

/// `refund_request_create` 성공 봉투.
class RefundRequestResult {
  const RefundRequestResult({
    required this.refundId,
    required this.subscriptionId,
    required this.amountCents,
    required this.rule,
    this.status = 'pending',
  });

  final String refundId;
  final String subscriptionId;
  final int amountCents;
  final String rule;
  final String status;

  factory RefundRequestResult.fromBody(Map<String, dynamic> b) {
    return RefundRequestResult(
      refundId: '${b['refund_id'] ?? ''}',
      subscriptionId: '${b['subscription_id'] ?? ''}',
      amountCents: _int(b['amount_cents']),
      rule: '${b['rule'] ?? ''}',
      status: '${b['status'] ?? 'pending'}',
    );
  }
}
