/// 알림 도메인 모델.
///
/// ★ 타입 판별은 키워드 포함 매칭이 아니라 [NotificationEventType.fromCode]
///   (정확 일치 17종)만 쓴다. 목록 밖 타입은 unknown → 기타(kind other)로
///   '일반 알림'으로 표시하되 숨기지 않는다(환불 포함). 맞춤의뢰 2종만
///   CR 게이트 OFF 로 레포 쿼리 단계에서 제외된다(서버 계약 17종 불변 —
///   notification_types.kGatedNotificationTypeCodes 참조).
///   type 원문(영문 코드)은 화면에 노출하지 않고, 한글 유형 라벨/본문만 쓴다.
library;

import 'notification_types.dart';

export 'notification_types.dart';

/// 본문이 비어 있을 때의 유형별 폴백(날조 아님 — 유형 안내만).
String _fallbackBody(NotificationKind kind) {
  switch (kind) {
    case NotificationKind.questionRoom:
      return '질문방에 새 소식이 있어요.';
    case NotificationKind.subscription:
      return '구독·결제 관련 알림이에요.';
    case NotificationKind.individualQuestion:
      return '개별질문에 새 소식이 있어요.';
    case NotificationKind.customRequest:
      return '맞춤의뢰 소식이 있어요.';
    case NotificationKind.other:
      return '새 알림이 있어요.';
  }
}

/// 알림 1건(조회·읽음 대상). 내부 id·type 원문은 화면에 노출하지 않는다.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.eventType,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.title,
    this.roomId,
    this.threadId,
    this.questionId,
  });

  final String id;

  /// 서버 type 정확 매핑(목록 밖 = unknown).
  final NotificationEventType eventType;

  /// data.title(서버 작성 제목). 없으면 본문만 표시.
  final String? title;

  final String body;
  final bool isRead;
  final DateTime createdAt;

  /// metadata.room_id — 질문방 정밀 딥링크 후속용(현재는 탭 이동만).
  final String? roomId;

  /// metadata.thread_id — 질문 스레드 정밀 딥링크 후속용.
  final String? threadId;

  /// metadata.question_id — 개별질문 정밀 딥링크 후속용.
  final String? questionId;

  /// 표시 분류(필터 칩·배지) — 타입에서 파생.
  NotificationKind get kind => notificationKindOf(eventType);

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        eventType: eventType,
        title: title,
        body: body,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        roomId: roomId,
        threadId: threadId,
        questionId: questionId,
      );

  /// 서버 행 → 모델. 누락 필드에 관대(크래시 금지): 모르는 타입은 unknown,
  /// 읽음은 is_read 우선 + 레거시 read 폴백, 빈 본문은 유형별 폴백.
  factory AppNotification.fromMap(Map<String, dynamic> map) {
    final NotificationEventType eventType =
        NotificationEventType.fromCode(map['type'] as String?);
    final NotificationKind kind = notificationKindOf(eventType);
    final String rawBody = (map['body'] as String?)?.trim() ?? '';
    final bool read =
        (map['is_read'] as bool?) ?? (map['read'] as bool?) ?? false;
    final Map<String, dynamic> data = _asMap(map['data']);
    final Map<String, dynamic> metadata = _asMap(map['metadata']);
    return AppNotification(
      id: map['id'] as String,
      eventType: eventType,
      title: _nonEmptyString(data['title']),
      body: rawBody.isEmpty ? _fallbackBody(kind) : rawBody,
      isRead: read,
      createdAt: _parseTime(map['created_at']),
      roomId: _nonEmptyString(metadata['room_id']),
      threadId: _nonEmptyString(metadata['thread_id']),
      questionId: _nonEmptyString(metadata['question_id']),
    );
  }
}

Map<String, dynamic> _asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((Object? k, Object? val) => MapEntry('$k', val));
  return const <String, dynamic>{};
}

String? _nonEmptyString(Object? v) {
  if (v == null) return null;
  final String s = '$v'.trim();
  return s.isEmpty ? null : s;
}

DateTime _parseTime(Object? v) {
  if (v is String && v.isNotEmpty) {
    return DateTime.tryParse(v)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}
