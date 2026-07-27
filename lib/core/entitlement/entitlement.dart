import 'package:supabase_flutter/supabase_flutter.dart';

import 'subscription_status.dart';

/// 권한/구독 상태(읽기 전용).
///
/// ★ Commerce-Zero: 앱은 결제하지 않고 '상태를 읽기만' 한다.
///   구독/충전이 필요하면 web_bridge 로 웹을 연다.
class Entitlement {
  const Entitlement({
    this.hasActiveSubscription = false,
    this.planTier,
  });

  /// 구독 자격 보유 여부([SubscriptionStatuses.entitled] — active 또는
  /// 잔여 기간이 살아 있는 cancel_scheduled).
  final bool hasActiveSubscription;

  /// 활성 구독의 plan_tier (limited|standard|premium). 없으면 null.
  final String? planTier;

  /// 앱 안에서 결제는 절대 하지 않는다(웹으로만 연결)을 명시하는 상수.
  static const bool inAppPurchaseEnabled = false;

  static const Entitlement none = Entitlement();
}

/// subscriptions 읽기 전용 리더(RLS: 당사자만).
class EntitlementReader {
  EntitlementReader._();

  /// 학생 본인의 자격 있는 구독을 읽는다.
  ///
  /// ※ 자격 집합은 [SubscriptionStatuses.entitled] 정본을 따른다 —
  ///   `active` 와 `cancel_scheduled`(해지 예약이지만 잔여 기간 유효).
  ///   past_due·pending·canceled·expired·refunded 는 자격 없음.
  ///   결제는 하지 않고 상태만 읽는다.
  static Future<Entitlement> fetchForStudent(
    SupabaseClient client,
    String studentId,
  ) async {
    try {
      final List<Map<String, dynamic>> rows = await client
          .from('subscriptions')
          .select('status, plan_tier')
          .eq('student_id', studentId)
          .inFilter('status', SubscriptionStatuses.entitledList);
      if (rows.isEmpty) return Entitlement.none;
      // 자격 행이 여럿이면 plan_tier 는 더 나은 상태(active)의 것을 쓴다.
      final Map<String, dynamic> row = rows.reduce(
        (Map<String, dynamic> a, Map<String, dynamic> b) =>
            SubscriptionStatuses.rank(b['status'] as String?) >
                    SubscriptionStatuses.rank(a['status'] as String?)
                ? b
                : a,
      );
      return Entitlement(
        hasActiveSubscription: true,
        planTier: (row['plan_tier'] as String?)?.trim(),
      );
    } catch (_) {
      return Entitlement.none;
    }
  }
}
