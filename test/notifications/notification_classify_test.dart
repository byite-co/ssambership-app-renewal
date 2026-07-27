import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/notifications/data/app_notification.dart';

/// 기대값 한 줄(정본 17종 테이블).
class _Expect {
  const _Expect(this.code, this.type, this.kind, this.dest);
  final String code;
  final NotificationEventType type;
  final NotificationKind kind;
  final NotificationDestination dest;
}

/// 서버 계약 스냅샷 §4.1 의 17종 전부 — 누락·오분류가 생기면 여기서 깨진다.
const List<_Expect> _canonical = <_Expect>[
  _Expect('question_answered', NotificationEventType.questionAnswered,
      NotificationKind.questionRoom, NotificationDestination.questionRoomTab),
  _Expect('new_order_message', NotificationEventType.newOrderMessage,
      NotificationKind.customRequest, NotificationDestination.stay),
  _Expect('new_application', NotificationEventType.newApplication,
      NotificationKind.customRequest, NotificationDestination.stay),
  _Expect(
      'mentor_subscription_price_changed',
      NotificationEventType.mentorSubscriptionPriceChanged,
      NotificationKind.subscription,
      NotificationDestination.myPage),
  _Expect(
      'mentor_termination_notice',
      NotificationEventType.mentorTerminationNotice,
      NotificationKind.subscription,
      NotificationDestination.myPage),
  _Expect(
      'mentor_termination_refund',
      NotificationEventType.mentorTerminationRefund,
      NotificationKind.subscription,
      NotificationDestination.myPage),
  _Expect('mentor_pause_notice', NotificationEventType.mentorPauseNotice,
      NotificationKind.subscription, NotificationDestination.myPage),
  _Expect(
      'individual_question_expired_refunded',
      NotificationEventType.individualQuestionExpiredRefunded,
      NotificationKind.individualQuestion,
      NotificationDestination.individualQuestionTab),
  _Expect(
      'individual_question_assigned',
      NotificationEventType.individualQuestionAssigned,
      NotificationKind.individualQuestion,
      NotificationDestination.individualQuestionTab),
  _Expect(
      'individual_question_claimed',
      NotificationEventType.individualQuestionClaimed,
      NotificationKind.individualQuestion,
      NotificationDestination.individualQuestionTab),
  _Expect(
      'individual_question_answered',
      NotificationEventType.individualQuestionAnswered,
      NotificationKind.individualQuestion,
      NotificationDestination.individualQuestionTab),
  _Expect(
      'individual_question_message',
      NotificationEventType.individualQuestionMessage,
      NotificationKind.individualQuestion,
      NotificationDestination.individualQuestionTab),
  _Expect(
      'individual_question_released',
      NotificationEventType.individualQuestionReleased,
      NotificationKind.individualQuestion,
      NotificationDestination.individualQuestionTab),
  _Expect(
      'subscription_renewal_upcoming',
      NotificationEventType.subscriptionRenewalUpcoming,
      NotificationKind.subscription,
      NotificationDestination.myPage),
  _Expect('subscription_expired', NotificationEventType.subscriptionExpired,
      NotificationKind.subscription, NotificationDestination.myPage),
  _Expect(
      'subscription_renewal_succeeded',
      NotificationEventType.subscriptionRenewalSucceeded,
      NotificationKind.subscription,
      NotificationDestination.myPage),
  _Expect(
      'subscription_renewal_failed_insufficient_cash',
      NotificationEventType.subscriptionRenewalFailedInsufficientCash,
      NotificationKind.subscription,
      NotificationDestination.myPage),
];

Map<String, dynamic> _row(
  String type, {
  String id = 'n1',
  String body = '본문',
  Object? data,
  Object? metadata,
  Object? isRead,
  Object? read,
}) =>
    <String, dynamic>{
      'id': id,
      'type': type,
      'body': body,
      'is_read': isRead,
      'read': read,
      'created_at': '2026-07-01T00:00:00+00:00',
      'data': data,
      'metadata': metadata,
    };

void main() {
  test('정본 17종 — 타입·분류·목적지 정확 매핑(테이블 전수)', () {
    expect(_canonical.length, NotificationEventType.canonicalCount,
        reason: '테이블은 정본 17종을 빠짐없이 다뤄야 한다');
    // enum 자체도 unknown 제외 17종이어야 한다.
    expect(
        NotificationEventType.values
            .where(
                (NotificationEventType v) => v != NotificationEventType.unknown)
            .length,
        NotificationEventType.canonicalCount);
    for (final _Expect e in _canonical) {
      final NotificationEventType t = NotificationEventType.fromCode(e.code);
      expect(t, e.type, reason: e.code);
      expect(notificationKindOf(t), e.kind, reason: e.code);
      expect(notificationDestinationOf(t), e.dest, reason: e.code);
    }
  });

  test('유사 문자열은 매핑되지 않는다(정확 일치 — 부분/접두 매칭 금지)', () {
    for (final String near in <String>[
      'question_answered_v2', // 접두 일치여도 목록 밖
      'individual_question', // 정본 코드의 접두부만
      'iq_answered', // 축약 접두어
      'subscription', // 그룹명만
      'refund', // 키워드만
    ]) {
      expect(
          NotificationEventType.fromCode(near), NotificationEventType.unknown,
          reason: near);
    }
  });

  test('대소문자·공백만 정규화 — QUESTION_ANSWERED 도 매핑된다', () {
    expect(NotificationEventType.fromCode('QUESTION_ANSWERED'),
        NotificationEventType.questionAnswered);
    expect(NotificationEventType.fromCode('  question_answered  '),
        NotificationEventType.questionAnswered);
    expect(NotificationEventType.fromCode('Individual_Question_Message'),
        NotificationEventType.individualQuestionMessage);
  });

  test('미지·빈 타입 → unknown = 기타 분류 + 이동 없음(숨기지 않음)', () {
    for (final String? raw in <String?>[null, '', 'weird_unknown']) {
      final NotificationEventType t = NotificationEventType.fromCode(raw);
      expect(t, NotificationEventType.unknown, reason: '$raw');
      expect(notificationKindOf(t), NotificationKind.other);
      expect(notificationDestinationOf(t), NotificationDestination.stay);
    }
  });

  test('회귀: 일시중지·구독종료 공지는 unknown 이 아니다(P2-15)', () {
    expect(NotificationEventType.fromCode('mentor_pause_notice'),
        isNot(NotificationEventType.unknown));
    expect(NotificationEventType.fromCode('mentor_termination_notice'),
        isNot(NotificationEventType.unknown));
  });

  test('fromMap: 타입·제목·본문·읽음·메타데이터 파싱', () {
    final AppNotification n = AppNotification.fromMap(_row(
      'question_answered',
      body: '답변이 도착했어요',
      isRead: false,
      data: <String, dynamic>{'title': '새 답변', 'link': '/rooms/r1'},
      metadata: <String, dynamic>{
        'event_key': 'k1',
        'room_id': 'r1',
        'thread_id': 't1',
      },
    ));
    expect(n.eventType, NotificationEventType.questionAnswered);
    expect(n.kind, NotificationKind.questionRoom);
    expect(n.title, '새 답변');
    expect(n.body, '답변이 도착했어요');
    expect(n.isRead, false);
    expect(n.roomId, 'r1');
    expect(n.threadId, 't1');
    expect(n.questionId, isNull);
  });

  test('fromMap: 개별질문 metadata.question_id 파싱', () {
    final AppNotification n = AppNotification.fromMap(_row(
      'individual_question_answered',
      metadata: <String, dynamic>{'question_id': 'q9'},
    ));
    expect(n.questionId, 'q9');
    expect(n.roomId, isNull);
  });

  test('fromMap: is_read 우선 + 레거시 read 폴백', () {
    expect(
        AppNotification.fromMap(_row('question_answered', isRead: true)).isRead,
        true);
    expect(
        AppNotification.fromMap(_row('question_answered', read: true)).isRead,
        true);
    // is_read 가 있으면 read 보다 우선.
    expect(
        AppNotification.fromMap(
                _row('question_answered', isRead: false, read: true))
            .isRead,
        false);
    expect(AppNotification.fromMap(_row('question_answered')).isRead, false);
  });

  test('본문 비면 유형별 폴백(날조 아님) — 맞춤의뢰·기타 포함', () {
    expect(AppNotification.fromMap(_row('new_order_message', body: '')).body,
        '맞춤의뢰 소식이 있어요.');
    expect(AppNotification.fromMap(_row('weird_unknown', body: '')).body,
        '새 알림이 있어요.');
    expect(AppNotification.fromMap(_row('subscription_expired', body: '')).body,
        '구독·결제 관련 알림이에요.');
    expect(AppNotification.fromMap(_row('question_answered', body: '')).body,
        '질문방에 새 소식이 있어요.');
    expect(
        AppNotification.fromMap(_row('individual_question_message', body: ''))
            .body,
        '개별질문에 새 소식이 있어요.');
  });

  test('fromMap: data/metadata 누락·이형에 관대(크래시 금지)', () {
    final AppNotification n = AppNotification.fromMap(<String, dynamic>{
      'id': 'x',
      'type': 'mentor_termination_refund',
      'created_at': '2026-07-01T00:00:00+00:00',
      // body/data/metadata/is_read/read 모두 누락
    });
    expect(n.eventType, NotificationEventType.mentorTerminationRefund);
    expect(n.kind, NotificationKind.subscription); // 환불도 숨기지 않는다
    expect(n.body.isNotEmpty, true);
    expect(n.isRead, false);
    expect(n.title, isNull);

    // metadata 가 이상한 타입이어도 무시.
    final AppNotification odd = AppNotification.fromMap(
        _row('question_answered', metadata: 'not-a-map', data: 42));
    expect(odd.roomId, isNull);
    expect(odd.title, isNull);
  });
}
