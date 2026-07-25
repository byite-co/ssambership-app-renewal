import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';

/// 뷰모델 순수 로직 — 특히 '미확정값 날조 금지' 규칙.
void main() {
  group('SubscriptionCardInfo', () {
    test('statusLabel: active→"구독 중", 아니면 "구독 만료"', () {
      const SubscriptionCardInfo active =
          SubscriptionCardInfo(mentorName: '멘토', isActive: true);
      const SubscriptionCardInfo expired =
          SubscriptionCardInfo(mentorName: '멘토', isActive: false);
      expect(active.statusLabel, '구독 중');
      expect(expired.statusLabel, '구독 만료');
    });

    test('planLabel: 확정 라벨(2026-07) — tier 코드를 한글 라벨로 매핑', () {
      const SubscriptionCardInfo c = SubscriptionCardInfo(
          mentorName: '멘토', isActive: true, planTier: 'standard');
      expect(c.planLabel, '스탠다드');
    });

    test('planLabel: 미지의 tier 코드 → null (영문 코드 날조·노출 없음)', () {
      const SubscriptionCardInfo c = SubscriptionCardInfo(
          mentorName: '멘토', isActive: true, planTier: 'unknown_tier');
      expect(c.planLabel, isNull);
    });
  });

  group('CashEntry', () {
    test('kindLabel: reason exact 매핑 정본 — 부호 추론 폐기(세션1 §5)', () {
      expect(
          CashEntry(deltaCents: 100, createdAt: _t, reason: 'cash_topup')
              .kindLabel,
          '충전');
      expect(CashEntry(deltaCents: -100, createdAt: _t).kindLabel, '기타 내역');
    });
  });

  group('CashSummary', () {
    test('balanceCents null → hasBalance=false (잔액 미확인 비움)', () {
      expect(const CashSummary().hasBalance, isFalse);
      expect(const CashSummary(balanceCents: 0).hasBalance, isTrue);
    });
  });
}

final DateTime _t = DateTime(2026, 7, 1);
