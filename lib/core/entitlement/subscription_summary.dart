import 'package:supabase_flutter/supabase_flutter.dart';

import 'subscription_status.dart';

/// 멘토별 구독 요약(읽기 전용). ★ S2 구독 레이어 — 질문방 레포가 아니다.
///
/// 질문방 화면의 '잔여/다음 갱신일'은 질문방 데이터가 아니라 구독에서 가져온다.
/// - isActive: [SubscriptionStatuses.entitled] (active·cancel_scheduled)
/// - nextRenewal: current_period_end (없으면 next_billing_at)
/// - remaining: 주간 문항 수가 미확정(plan_constants 값 비움 + DB에 잔여 컬럼 없음)이라
///   현재는 null(미정). 확정되면 채운다. 게이팅은 isActive 로 한다(미정이면 활성=가능).
class SubscriptionSummary {
  const SubscriptionSummary({
    required this.mentorId,
    required this.isActive,
    this.id,
    this.status,
    this.planTier,
    this.nextRenewal,
    this.remaining,
    this.cancelAtPeriodEnd = false,
  });

  final String mentorId;

  /// `subscriptions.id` — 해지 예약·취소·환불 신청 래퍼의 인자(A-4b). 화면 미노출.
  final String? id;

  /// `subscriptions.cancel_at_period_end` — 해지 예약 플래그. DB-4 199 는 status 를
  /// 바꾸지 않고 이 플래그만 세우므로(active 유지) 해지 예정 표시는 이 값을 본다.
  final bool cancelAtPeriodEnd;

  /// 구독 자격 보유 여부. ★ 'active 상태'가 아니라 **자격 집합** 판정이다 —
  /// 해지 예약(cancel_scheduled)도 잔여 기간이 살아 있어 true 다.
  final bool isActive;

  /// 원본 상태값(active/past_due/canceled/expired/pending/refunded/cancel_scheduled).
  /// 표시 세분화용 — 화면엔 [subscriptionStatusDisplay] 로 한글 라벨만 노출한다.
  final String? status;
  final String? planTier;
  final DateTime? nextRenewal;
  final int? remaining;

  /// 질문 가능 여부. 활성 구독 + (잔여 미정이거나 1개 이상).
  bool get canAsk => isActive && (remaining == null || remaining! > 0);

  /// 해지 예정(기간 말 해지) — 플래그 또는 상태값 어느 쪽이든.
  bool get isCancelScheduled =>
      cancelAtPeriodEnd ||
      status?.trim() == SubscriptionStatuses.cancelScheduled;
}

/// subscriptions 읽기 전용 리더(RLS: 당사자만). 멘토별 1건으로 요약.
class SubscriptionReader {
  SubscriptionReader._();

  /// 학생의 모든 구독을 멘토별로 요약. 같은 멘토에 여러 건이면
  /// active → cancel_scheduled → 그 외 순으로 우선하고, 같은 순위면
  /// 갱신일이 늦은 것을 택한다.
  static Future<Map<String, SubscriptionSummary>> fetchForStudent(
    SupabaseClient client,
    String studentId,
  ) async {
    final List<Map<String, dynamic>> rows = await client
        .from('subscriptions')
        .select('id, mentor_id, status, plan_tier, current_period_end, '
            'next_billing_at, cancel_at_period_end')
        .eq('student_id', studentId);

    final Map<String, SubscriptionSummary> byMentor =
        <String, SubscriptionSummary>{};
    for (final Map<String, dynamic> r in rows) {
      final String? mentorId = r['mentor_id'] as String?;
      if (mentorId == null) continue;
      final String? statusRaw = (r['status'] as String?)?.trim();
      final bool isActive = SubscriptionStatuses.isEntitled(statusRaw);
      final SubscriptionSummary s = SubscriptionSummary(
        mentorId: mentorId,
        isActive: isActive,
        id: r['id'] as String?,
        cancelAtPeriodEnd: r['cancel_at_period_end'] == true,
        status: statusRaw,
        planTier: (r['plan_tier'] as String?)?.trim(),
        nextRenewal:
            _time(r['current_period_end']) ?? _time(r['next_billing_at']),
        remaining: null, // 주간 문항수 미확정 → 미정
      );
      final SubscriptionSummary? prev = byMentor[mentorId];
      if (prev == null || _isBetter(s, prev)) {
        byMentor[mentorId] = s;
      }
    }
    return byMentor;
  }

  static bool _isBetter(SubscriptionSummary a, SubscriptionSummary b) {
    // active 우선 · cancel_scheduled 차순(둘 다 자격이지만 active 가 낫다) ·
    // 나머지는 종전대로 갱신일이 늦은 것.
    final int aRank = SubscriptionStatuses.rank(a.status);
    final int bRank = SubscriptionStatuses.rank(b.status);
    if (aRank != bRank) return aRank > bRank;
    final DateTime ar = a.nextRenewal ?? DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime br = b.nextRenewal ?? DateTime.fromMillisecondsSinceEpoch(0);
    return ar.isAfter(br); // 갱신일 늦은 것
  }

  static DateTime? _time(Object? v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
    return null;
  }
}
