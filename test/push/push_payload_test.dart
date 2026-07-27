import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/core/push/push_payload.dart';
import 'package:ssambership_app/features/notifications/data/notification_types.dart';

/// 수신 payload 파싱(순수). 발송 빌더는 제거됨 — 발송은 서버 outbox worker 단독.
void main() {
  group('PushPayload.fromRemote', () {
    test('type 은 정본 17종 코드로 정확 일치 매핑된다', () {
      final PushPayload p = PushPayload.fromRemote(
        const <String, dynamic>{'type': 'question_answered', 'room_id': 'r-1'},
        title: '답변',
        body: '내용',
      );
      expect(p.type, NotificationEventType.questionAnswered);
      expect(p.roomId, 'r-1');
      expect(p.title, '답변');
      expect(p.body, '내용');
    });

    test('목록 밖 타입·빈 타입은 unknown(키워드 포함 매칭 금지)', () {
      expect(
        PushPayload.fromRemote(const <String, dynamic>{'type': 'made_up'}).type,
        NotificationEventType.unknown,
      );
      expect(
        PushPayload.fromRemote(const <String, dynamic>{}).type,
        NotificationEventType.unknown,
      );
      // 부분 문자열 매칭 금지: 접두어가 같아도 정확 일치가 아니면 unknown.
      expect(
        PushPayload.fromRemote(
            const <String, dynamic>{'type': 'question_answered_v2'}).type,
        NotificationEventType.unknown,
      );
    });

    test('id 필드: room_id/thread_id/question_id 를 개별 보관, 빈 값은 null', () {
      final PushPayload p = PushPayload.fromRemote(const <String, dynamic>{
        'type': 'individual_question_answered',
        'thread_id': 't-1',
        'question_id': 'q-1',
        'room_id': '  ',
      });
      expect(p.threadId, 't-1');
      expect(p.questionId, 'q-1');
      expect(p.roomId, isNull); // 공백만 → null.
    });

    test('eventId: notification_id 우선, 없으면 event_key, 둘 다 없으면 빈 문자열', () {
      expect(
        PushPayload.fromRemote(const <String, dynamic>{
          'notification_id': 'n-1',
          'event_key': 'ek-1',
        }).eventId,
        'n-1',
      );
      expect(
        PushPayload.fromRemote(const <String, dynamic>{'event_key': 'ek-1'})
            .eventId,
        'ek-1',
      );
      expect(PushPayload.fromRemote(const <String, dynamic>{}).eventId, '');
    });

    test('외부 경로 필드(link/url)는 파싱 단계에서 버려진다(보관 필드 없음)', () {
      final PushPayload p = PushPayload.fromRemote(const <String, dynamic>{
        'type': 'subscription_expired',
        'link': 'https://evil.example/wallet/charge',
        'url': 'intent://malicious',
      });
      // PushPayload 는 link/url 을 담을 자리가 아예 없다 — 타입/id/eventId 만.
      expect(p.type, NotificationEventType.subscriptionExpired);
      expect(p.roomId, isNull);
      expect(p.threadId, isNull);
      expect(p.questionId, isNull);
      expect(p.eventId, '');
    });

    test('문자열 아닌 값은 무시한다(형 안전)', () {
      final PushPayload p = PushPayload.fromRemote(const <String, dynamic>{
        'type': 42,
        'room_id': 7,
        'notification_id': true,
      });
      expect(p.type, NotificationEventType.unknown);
      expect(p.roomId, isNull);
      expect(p.eventId, '');
    });
  });
}
