import '../../core/entitlement/subscription_status.dart';
import '../../core/entitlement/subscription_summary.dart';
import '../../core/entitlement/weekly_question_usage.dart';
import '../format/formatters.dart';

/// 구독·주간 한도 → 화면 문장(design-tokens §6 — 명사 라벨 대신 문장).
///
/// 값이 없으면 null 을 돌려 줄을 생략한다(날조 금지). 숫자·날짜는 RPC 반환값만 쓴다.
class SubscriptionCopy {
  SubscriptionCopy._();

  /// '9월 9일에 갱신돼요' / '9월 15일에 해지돼요' / '구독 중이에요' / '구독이 끝났어요'.
  static String? subscriptionSentence(SubscriptionSummary? sub) {
    if (sub == null) return null;
    if (!sub.isActive) return '구독이 끝났어요';
    final DateTime? when = sub.nextRenewal;
    if (sub.status?.trim() == SubscriptionStatuses.cancelScheduled) {
      return when == null ? '해지 예정이에요' : '${Formatters.monthDay(when)}에 해지돼요';
    }
    return when == null ? '구독 중이에요' : '${Formatters.monthDay(when)}에 갱신돼요';
  }

  /// '질문 무제한' / '이번 주 9개 중 9개 남았어요' / '이번 주 질문을 다 썼어요'.
  /// 한도 정보가 없으면 null.
  static String? quotaSentence(WeeklyQuestionUsage? usage) {
    if (usage == null || !usage.hasQuota) return null;
    if (usage.isEffectivelyUnlimited) return '질문 무제한';
    if (usage.remaining <= 0) return '이번 주 질문을 다 썼어요';
    return '이번 주 ${usage.limit}개 중 ${usage.remaining}개 남았어요';
  }

  /// 주간 한도가 다시 채워지는 날 — '8월 27일 목요일에 다시 채워져요'. 없으면 null.
  static String? refillSentence(WeeklyQuestionUsage? usage) {
    final DateTime? end = usage?.weekEnd;
    if (end == null) return null;
    return '${Formatters.monthDay(end)} ${Formatters.weekday(end)}에 다시 채워져요';
  }
}
