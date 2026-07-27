import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mypage/data/mypage_models.dart';
import 'package:ssambership_app/features/mypage/format/cash_format.dart';

/// 원장 라벨 정본화(세션1 §5) — reason exact 매핑 4종 + 미지 fallback.
/// contains/접두사/부호 추론 금지, 환불(+delta)을 '충전'으로 표기하지 않는다.
void main() {
  DateTime t() => DateTime(2026, 7, 24);

  test('정본 4종 exact 라벨', () {
    expect(cashLedgerReasonLabel('cash_topup'), '충전');
    expect(cashLedgerReasonLabel('subscription_payment'), '구독 결제');
    expect(
        cashLedgerReasonLabel('individual_question_escrow_hold'), '개별질문 안전 결제');
    expect(cashLedgerReasonLabel('individual_question_refund'), '개별질문 환불');
  });

  test('환불과 충전 구분 — 둘 다 +delta 지만 라벨은 reason 으로만 갈린다', () {
    final CashEntry refund = CashEntry(
        deltaCents: 999000,
        createdAt: t(),
        reason: 'individual_question_refund');
    final CashEntry topup =
        CashEntry(deltaCents: 999000, createdAt: t(), reason: 'cash_topup');
    expect(refund.kindLabel, '개별질문 환불');
    expect(refund.kindLabel, isNot('충전'));
    expect(topup.kindLabel, '충전');
    // 부호·색 계약(실제 delta 기반)은 그대로.
    expect(refund.isCredit, isTrue);
  });

  test('부분 문자열·접두사는 매칭되지 않는다(exact only)', () {
    expect(cashLedgerReasonLabel('cash_topup_extra'), '기타 내역');
    expect(cashLedgerReasonLabel('individual_question'), '기타 내역');
    expect(cashLedgerReasonLabel('subscription_payment '), '기타 내역');
  });

  test('미지·null·빈 값 → 기타 내역 (크래시 없음·영문 코드 비노출)', () {
    expect(cashLedgerReasonLabel('subscription_renewal'), '기타 내역');
    expect(cashLedgerReasonLabel(null), '기타 내역');
    expect(cashLedgerReasonLabel(''), '기타 내역');
    expect(CashEntry(deltaCents: -100, createdAt: t()).kindLabel, '기타 내역');
  });

  test('양수·음수 금액 표기 회귀 없음(부호는 delta 정본)', () {
    expect(CashFormat.signedWon(500000), '+5,000원');
    expect(CashFormat.signedWon(-120000), '-1,200원');
    expect(
        CashEntry(
                deltaCents: -120000,
                createdAt: t(),
                reason: 'subscription_payment')
            .isCredit,
        isFalse);
  });
}
