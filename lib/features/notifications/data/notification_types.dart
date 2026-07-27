/// 알림 이벤트 타입 정본(17종) — staging 트리거 소스 실추출로 확정
/// (docs/APP_V16_SERVER_CONTRACT_SNAPSHOT.md §4.1). 키워드 포함 매칭 금지:
/// 정확한 문자열 일치만 사용하고, 목록 밖 타입은 [unknown](일반 알림 표시 ·
/// 이동 없음)으로 다룬다. 내부 영문 코드는 화면에 노출하지 않는다.
///
/// ★ 서버 계약 vs 앱 출시 표면(2026-07 CR 게이트 OFF): 정본 17종 enum·서버
///   producer·DB 이벤트 계약은 그대로다. 다만 이번 출시에서 맞춤의뢰 CR 게이트가
///   OFF 이므로 앱 '표시 표면'은 [kGatedNotificationTypeCodes] 2종을 목록 쿼리
///   단계에서 제외한다(부분 문자열 아님 — exact code). 두 개념을 혼동하지 말 것.
library;

/// CR 게이트 OFF 로 앱 표면에서 노출하지 않는 맞춤의뢰 이벤트 코드(exact 2종).
/// 서버 발송·정본 enum 은 삭제하지 않는다 — 목록 조회의 DB 단계 제외에만 쓴다.
const Set<String> kGatedNotificationTypeCodes = <String>{
  'new_order_message',
  'new_application',
};

/// 서버 `notifications.type` 정확 매핑.
enum NotificationEventType {
  questionAnswered('question_answered'),
  newOrderMessage('new_order_message'),
  newApplication('new_application'),
  mentorSubscriptionPriceChanged('mentor_subscription_price_changed'),
  mentorTerminationNotice('mentor_termination_notice'),
  mentorTerminationRefund('mentor_termination_refund'),
  mentorPauseNotice('mentor_pause_notice'),
  individualQuestionExpiredRefunded('individual_question_expired_refunded'),
  individualQuestionAssigned('individual_question_assigned'),
  individualQuestionClaimed('individual_question_claimed'),
  individualQuestionAnswered('individual_question_answered'),
  individualQuestionMessage('individual_question_message'),
  individualQuestionReleased('individual_question_released'),
  subscriptionRenewalUpcoming('subscription_renewal_upcoming'),
  subscriptionExpired('subscription_expired'),
  subscriptionRenewalSucceeded('subscription_renewal_succeeded'),
  subscriptionRenewalFailedInsufficientCash(
      'subscription_renewal_failed_insufficient_cash'),

  /// 목록 밖 타입 — 크래시 없이 일반 알림으로만 표시, URL/화면 이동 금지.
  unknown('');

  const NotificationEventType(this.code);

  /// 서버 type 문자열(정확 일치용). unknown 은 빈 문자열.
  final String code;

  /// 정확 일치 매핑(대소문자·공백만 정규화, 부분 문자열 매칭 금지).
  static NotificationEventType fromCode(String? raw) {
    final String t = raw?.trim().toLowerCase() ?? '';
    if (t.isEmpty) return NotificationEventType.unknown;
    for (final NotificationEventType v in NotificationEventType.values) {
      if (v != NotificationEventType.unknown && v.code == t) return v;
    }
    return NotificationEventType.unknown;
  }

  /// 정본 17종(unknown 제외).
  static const int canonicalCount = 17;
}

/// 화면 분류(필터 칩·배지). 표시용 그룹 — 서버 groups(qna/order/subscription/
/// refund/system)와는 별개의 UI 분류다.
enum NotificationKind {
  questionRoom,
  individualQuestion,
  subscription,
  customRequest,
  other,
}

/// 분류 한글 라벨(내부 영문 코드 비노출).
String notificationKindLabel(NotificationKind kind) {
  switch (kind) {
    case NotificationKind.questionRoom:
      return '질문방';
    case NotificationKind.individualQuestion:
      return '개별질문';
    case NotificationKind.subscription:
      return '구독·결제';
    case NotificationKind.customRequest:
      return '맞춤의뢰';
    case NotificationKind.other:
      return '기타';
  }
}

/// 타입 → 표시 분류. 환불·미지 타입은 숨기지 않는다. 맞춤의뢰 2종은 CR 게이트
/// OFF 로 목록 쿼리에서 제외되지만(kGatedNotificationTypeCodes), 분류 자체는
/// 정본 계약으로 유지한다(게이트 재개 시 재사용·안전망).
NotificationKind notificationKindOf(NotificationEventType type) {
  switch (type) {
    case NotificationEventType.questionAnswered:
      return NotificationKind.questionRoom;
    case NotificationEventType.newOrderMessage:
    case NotificationEventType.newApplication:
      return NotificationKind.customRequest;
    case NotificationEventType.individualQuestionExpiredRefunded:
    case NotificationEventType.individualQuestionAssigned:
    case NotificationEventType.individualQuestionClaimed:
    case NotificationEventType.individualQuestionAnswered:
    case NotificationEventType.individualQuestionMessage:
    case NotificationEventType.individualQuestionReleased:
      return NotificationKind.individualQuestion;
    case NotificationEventType.mentorSubscriptionPriceChanged:
    case NotificationEventType.mentorTerminationNotice:
    case NotificationEventType.mentorTerminationRefund:
    case NotificationEventType.mentorPauseNotice:
    case NotificationEventType.subscriptionRenewalUpcoming:
    case NotificationEventType.subscriptionExpired:
    case NotificationEventType.subscriptionRenewalSucceeded:
    case NotificationEventType.subscriptionRenewalFailedInsufficientCash:
      return NotificationKind.subscription;
    case NotificationEventType.unknown:
      return NotificationKind.other;
  }
}

/// 앱 내부 허용 목적지 — 임의 URL·외부 scheme·미지 route 실행 금지(P2-18).
/// 현 라우터는 탭 단위 이동만 지원하므로 목적지도 탭 수준으로 고정한다.
enum NotificationDestination {
  /// 질문방 탭(question_answered — metadata room_id/thread_id 는 후속 정밀 이동용).
  questionRoomTab,

  /// 개별질문 탭(iq_* — metadata question_id).
  individualQuestionTab,

  /// 마이페이지(구독 관리 진입). ★앱 내 결제·충전 화면 금지(Commerce-Zero) —
  /// 서버 link 의 /wallet/charge 는 따라가지 않고 구독 안내 화면까지만 연다.
  myPage,

  /// 이동 없음 — 알림 목록에서 내용만 확인(맞춤의뢰 등 앱 내 전용 화면 부재,
  /// unknown 타입 포함).
  stay,
}

/// 타입 → 허용 목적지 정본 매핑(17종 전부 명시).
NotificationDestination notificationDestinationOf(NotificationEventType type) {
  switch (type) {
    case NotificationEventType.questionAnswered:
      return NotificationDestination.questionRoomTab;
    case NotificationEventType.individualQuestionExpiredRefunded:
    case NotificationEventType.individualQuestionAssigned:
    case NotificationEventType.individualQuestionClaimed:
    case NotificationEventType.individualQuestionAnswered:
    case NotificationEventType.individualQuestionMessage:
    case NotificationEventType.individualQuestionReleased:
      return NotificationDestination.individualQuestionTab;
    case NotificationEventType.mentorSubscriptionPriceChanged:
    case NotificationEventType.mentorTerminationNotice:
    case NotificationEventType.mentorTerminationRefund:
    case NotificationEventType.mentorPauseNotice:
    case NotificationEventType.subscriptionRenewalUpcoming:
    case NotificationEventType.subscriptionExpired:
    case NotificationEventType.subscriptionRenewalSucceeded:
    case NotificationEventType.subscriptionRenewalFailedInsufficientCash:
      return NotificationDestination.myPage;
    case NotificationEventType.newOrderMessage:
    case NotificationEventType.newApplication:
      // 맞춤의뢰 전용 화면이 앱에 없다 — 숨기지 않되 안전하게 목록에 머문다.
      return NotificationDestination.stay;
    case NotificationEventType.unknown:
      return NotificationDestination.stay;
  }
}
