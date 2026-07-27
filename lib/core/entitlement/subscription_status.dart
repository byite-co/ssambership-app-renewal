/// `subscriptions.status` 판정 정본 — 자격 집합을 **한 곳에서만** 정의한다.
///
/// 실 enum 7종: pending · active · past_due · cancel_scheduled · canceled ·
/// expired · refunded.
///
/// ★ `cancel_scheduled` 는 해지 '예약' 상태일 뿐 잔여 기간이 살아 있으므로
///   자격에 포함한다(오너 확정 2). 자격 판정이 화면마다 갈리지 않도록
///   문자열 리터럴을 두 번 쓰지 않고 이 상수를 공유한다.
///
/// ★ 여기서 말하는 자격은 **구독 자격(질문 가능 여부)** 이다. 리뷰 자격은
///   별개 축이며 웹·서버 소관이다 — 앱에 리뷰 자격 로직을 두지 않는다.
class SubscriptionStatuses {
  const SubscriptionStatuses._();

  static const String active = 'active';
  static const String cancelScheduled = 'cancel_scheduled';

  /// 잔여 기간이 살아 있어 구독 자격이 유지되는 상태.
  static const Set<String> entitled = <String>{active, cancelScheduled};

  /// DB `in` 필터용(정렬 고정 — active 우선).
  static const List<String> entitledList = <String>[active, cancelScheduled];

  /// 자격 여부. 공백은 정규화하고, null·미지 값은 자격 없음이다.
  static bool isEntitled(String? raw) => entitled.contains(raw?.trim());

  /// 자격 상태 간 우선순위(클수록 낫다). 둘 다 자격이지만 active 가 더 낫다.
  static int rank(String? raw) {
    switch (raw?.trim()) {
      case active:
        return 2;
      case cancelScheduled:
        return 1;
      default:
        return 0;
    }
  }
}
