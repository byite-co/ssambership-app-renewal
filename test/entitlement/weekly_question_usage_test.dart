import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/entitlement/weekly_question_usage.dart';

/// A2: 주간 질문 사용량 파싱·표시·차단 규칙(순수, DB·네트워크 미접촉).
/// RPC get_weekly_question_usage 반환 JSON을 mock 으로 검증한다.
void main() {
  Map<String, Object?> rpc({
    required int used,
    required int limit,
    int? remaining,
    bool? canAsk,
    String? tier,
    String? weekEnd,
  }) =>
      <String, Object?>{
        'used': used,
        'limit': limit,
        'remaining': remaining,
        'can_ask': canAsk,
        'plan_tier': tier,
        'week_end': weekEnd,
      };

  test('standard 한도 9, 사용 3 → can_ask=true, 잔여 라벨 표시', () {
    final WeeklyQuestionUsage? u = WeeklyQuestionUsage.fromRpc(
        rpc(used: 3, limit: 9, remaining: 6, canAsk: true, tier: 'standard'));
    expect(u, isNotNull);
    expect(u!.canAsk, isTrue);
    expect(u.remaining, 6);
    expect(u.remainingLabel, '이번 주 남은 질문 6개');
  });

  test('한도 소진(can_ask=false) → 차단 문구에 사용/한도 포함', () {
    final WeeklyQuestionUsage u = WeeklyQuestionUsage.fromRpc(
        rpc(used: 4, limit: 4, remaining: 0, canAsk: false, tier: 'limited'))!;
    expect(u.canAsk, isFalse);
    expect(u.blockMessage, contains('사용 4/4'));
    expect(u.blockMessage, contains('모두 사용'));
  });

  test('프리미엄(limit 999)은 큰 잔여수 대신 "질문 가능"으로 표시', () {
    final WeeklyQuestionUsage u = WeeklyQuestionUsage.fromRpc(rpc(
        used: 1, limit: 999, remaining: 998, canAsk: true, tier: 'premium'))!;
    expect(u.isEffectivelyUnlimited, isTrue);
    expect(u.remainingLabel, '이번 주 질문 가능');
  });

  test('can_ask 누락 시 used<limit 로 폴백', () {
    final WeeklyQuestionUsage u =
        WeeklyQuestionUsage.fromRpc(rpc(used: 2, limit: 9))!;
    expect(u.canAsk, isTrue);
    final WeeklyQuestionUsage full =
        WeeklyQuestionUsage.fromRpc(rpc(used: 9, limit: 9))!;
    expect(full.canAsk, isFalse);
  });

  test('한도 0(비구독)이면 잔여 라벨 없음', () {
    final WeeklyQuestionUsage u =
        WeeklyQuestionUsage.fromRpc(rpc(used: 0, limit: 0, canAsk: false))!;
    expect(u.hasQuota, isFalse);
    expect(u.remainingLabel, isNull);
  });

  test('예상치 못한 형태(List/null)면 null 반환', () {
    expect(WeeklyQuestionUsage.fromRpc(null), isNull);
    expect(WeeklyQuestionUsage.fromRpc(<Object?>[1, 2, 3]), isNull);
  });

  group('planQuotaLabel (마이페이지 구독 카드용, RPC 값만 사용)', () {
    test('일반 플랜은 "주 N개 질문 · 잔여 X/N"', () {
      final WeeklyQuestionUsage u = WeeklyQuestionUsage.fromRpc(rpc(
          used: 3, limit: 9, remaining: 6, canAsk: true, tier: 'standard'))!;
      expect(u.planQuotaLabel, '주 9개 질문 · 잔여 6/9');
    });

    test('프리미엄(limit 999)은 "주 무제한 질문"', () {
      final WeeklyQuestionUsage u = WeeklyQuestionUsage.fromRpc(rpc(
          used: 1, limit: 999, remaining: 998, canAsk: true, tier: 'premium'))!;
      expect(u.planQuotaLabel, '주 무제한 질문');
    });

    test('한도 0(비구독)이면 null(표시 생략)', () {
      final WeeklyQuestionUsage u =
          WeeklyQuestionUsage.fromRpc(rpc(used: 0, limit: 0, canAsk: false))!;
      expect(u.planQuotaLabel, isNull);
    });
  });
}
