import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/entitlement/subscription_status.dart';
import 'package:ssambership_app/core/entitlement/subscription_status_display.dart';
import 'package:ssambership_app/core/entitlement/subscription_summary.dart';

/// 구독 자격에 `cancel_scheduled` 포함(오너 확정 2).
///
/// 해지 '예약' 상태는 잔여 기간이 살아 있으므로 자격에 포함한다. 판정 집합은
/// [SubscriptionStatuses] 한 곳에만 있고 두 소비처(EntitlementReader ·
/// SubscriptionSummary)가 그것을 공유한다 — 화면마다 판정이 갈리지 않는다.

SubscriptionSummary _sum({
  required String? status,
  String mentorId = 'm-1',
  int? remaining,
}) =>
    SubscriptionSummary(
      mentorId: mentorId,
      isActive: SubscriptionStatuses.isEntitled(status),
      status: status,
      remaining: remaining,
    );

void main() {
  group('자격 집합 정본(SubscriptionStatuses)', () {
    test('실 enum 7종 전수 — active·cancel_scheduled 만 자격', () {
      const Map<String, bool> expected = <String, bool>{
        'active': true,
        'cancel_scheduled': true,
        'pending': false,
        'past_due': false,
        'canceled': false,
        'expired': false,
        'refunded': false,
      };
      expected.forEach((String status, bool entitled) {
        expect(SubscriptionStatuses.isEntitled(status), entitled,
            reason: status);
      });
    });

    test('null·빈 값·미지 상태는 자격 없음(fail-closed)', () {
      expect(SubscriptionStatuses.isEntitled(null), isFalse);
      expect(SubscriptionStatuses.isEntitled(''), isFalse);
      expect(SubscriptionStatuses.isEntitled('cancelled'), isFalse);
      expect(SubscriptionStatuses.isEntitled('ACTIVE'), isFalse,
          reason: '서버 enum 은 소문자 — 관용 해석 금지');
    });

    test('공백은 정규화한다', () {
      expect(SubscriptionStatuses.isEntitled(' active '), isTrue);
      expect(SubscriptionStatuses.isEntitled(' cancel_scheduled '), isTrue);
    });

    test('우선순위: active > cancel_scheduled > 그 외', () {
      expect(SubscriptionStatuses.rank('active'), 2);
      expect(SubscriptionStatuses.rank('cancel_scheduled'), 1);
      expect(SubscriptionStatuses.rank('past_due'), 0);
      expect(SubscriptionStatuses.rank(null), 0);
    });

    test('DB in 필터 목록이 자격 집합과 일치한다(리터럴 이중 정의 금지)', () {
      expect(SubscriptionStatuses.entitledList.toSet(),
          SubscriptionStatuses.entitled);
    });
  });

  group('SubscriptionSummary.isActive — 두 번째 하드코딩 지점', () {
    test('cancel_scheduled → isActive true(해지 예약이지만 잔여 기간 유효)', () {
      expect(_sum(status: 'cancel_scheduled').isActive, isTrue);
    });

    test('past_due·pending·canceled·expired·refunded → isActive false', () {
      for (final String s in <String>[
        'past_due',
        'pending',
        'canceled',
        'expired',
        'refunded',
      ]) {
        expect(_sum(status: s).isActive, isFalse, reason: s);
      }
    });
  });

  group('행동 변경 — 해지 예약 사용자의 질문 생성 CTA(canAsk)', () {
    // canAsk 는 question_list_screen 의 _canAsk → 질문 생성 CTA 를 좌우한다.
    test('해지 예약 + 잔여 미정(null) → canAsk true (CTA 새로 열림 — 의도된 변경)', () {
      expect(_sum(status: 'cancel_scheduled').canAsk, isTrue);
    });

    test('해지 예약 + 잔여 1 이상 → canAsk true', () {
      expect(_sum(status: 'cancel_scheduled', remaining: 3).canAsk, isTrue);
    });

    test('★ 해지 예약 + 잔여 0 → canAsk false (여전히 닫혀 있어야 한다)', () {
      expect(_sum(status: 'cancel_scheduled', remaining: 0).canAsk, isFalse);
    });

    test('active + 잔여 0 → canAsk false(종전 동작 불변)', () {
      expect(_sum(status: 'active', remaining: 0).canAsk, isFalse);
    });

    test('자격 없는 상태는 잔여가 남아 있어도 canAsk false', () {
      expect(_sum(status: 'past_due', remaining: 5).canAsk, isFalse);
      expect(_sum(status: 'expired', remaining: 5).canAsk, isFalse);
    });
  });

  group('_isBetter 우선순위 — 같은 멘토 다건 요약', () {
    // fetchForStudent 의 선택 규칙을 순수 계층에서 고정한다.
    SubscriptionSummary better(SubscriptionSummary a, SubscriptionSummary b) {
      final int ar = SubscriptionStatuses.rank(a.status);
      final int br = SubscriptionStatuses.rank(b.status);
      if (ar != br) return ar > br ? a : b;
      return a; // 동순위는 갱신일 규칙(기존 유지) — 여기선 상태 순위만 검증
    }

    test('active 가 cancel_scheduled 보다 낫다(둘 다 자격)', () {
      final SubscriptionSummary a = _sum(status: 'active');
      final SubscriptionSummary c = _sum(status: 'cancel_scheduled');
      expect(better(a, c).status, 'active');
      expect(better(c, a).status, 'active');
    });

    test('cancel_scheduled 가 자격 없는 상태보다 낫다', () {
      final SubscriptionSummary c = _sum(status: 'cancel_scheduled');
      final SubscriptionSummary e = _sum(status: 'expired');
      expect(better(c, e).status, 'cancel_scheduled');
      expect(better(e, c).status, 'cancel_scheduled');
    });
  });

  group('표시는 별개 축 — 자격 포함이 라벨을 바꾸지 않는다', () {
    test('cancel_scheduled 는 자격이어도 라벨은 "구독 만료 예정"', () {
      final SubscriptionStatusDisplay d =
          subscriptionStatusDisplay('cancel_scheduled', isActive: true);
      expect(d.label, '구독 만료 예정');
    });

    test('active 라벨은 종전대로 "이용 중"', () {
      expect(subscriptionStatusDisplay('active', isActive: true).label, '이용 중');
    });
  });
}
