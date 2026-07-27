import 'package:flutter/foundation.dart';

import '../../features/notifications/data/notification_types.dart';

/// 수신 푸시 payload(파싱 결과). ★ 앱은 '수신 전용' — 발송 payload 빌더는 제거됨
/// (발송은 서버 outbox worker 단독: record_domain_notification → notification_outbox
/// → deliveries).
///
/// 서버 deliveries 의 data 필드 계약:
/// - `type`: 정본 17종 코드(notification_types.dart, 정확 일치 — 목록 밖은 unknown)
/// - 선택 id: `room_id` / `thread_id` / `question_id`
/// - 중복 제거용: `notification_id`(우선) / `event_key`(폴백)
/// - ★ `link`/`url` 등 외부 경로 필드는 '무시'한다 — payload 로 URL/외부 scheme 을
///   실행하지 않는다(허용 목적지는 notificationDestinationOf 의 탭뿐).
@immutable
class PushPayload {
  const PushPayload({
    required this.type,
    this.title = '',
    this.body = '',
    this.roomId,
    this.threadId,
    this.questionId,
    this.eventId = '',
  });

  /// 정본 17종 매핑(목록 밖은 unknown — 이동 없음).
  final NotificationEventType type;

  /// 표시 문구(notification 파트, 없으면 빈 문자열).
  final String title;
  final String body;

  /// 정밀 딥링크용 내부 id(화면 비노출).
  final String? roomId;
  final String? threadId;
  final String? questionId;

  /// 중복 수신 제거 키: notification_id 우선, 없으면 event_key, 둘 다 없으면 빈 문자열
  /// (빈 문자열 = dedup 불가 — 매 수신을 새 이벤트로 취급).
  final String eventId;

  /// 수신 원격 메시지(data + notification) → payload.
  /// ★ 미지 필드는 버린다(link/url 포함) — 원본 map 을 보관하지 않는다.
  factory PushPayload.fromRemote(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    return PushPayload(
      type: NotificationEventType.fromCode(_string(data['type'])),
      title: title ?? '',
      body: body ?? '',
      roomId: _string(data['room_id']),
      threadId: _string(data['thread_id']),
      questionId: _string(data['question_id']),
      eventId:
          _string(data['notification_id']) ?? _string(data['event_key']) ?? '',
    );
  }

  static String? _string(Object? value) {
    if (value is String) {
      final String t = value.trim();
      return t.isEmpty ? null : t;
    }
    return null;
  }
}
