import 'package:flutter/foundation.dart';

import '../../app/app_tabs.dart';
import '../../features/notifications/data/notification_types.dart';

/// 내부 id(UUID v4 등) 형식 검증 — 딥링크는 검증된 UUID 로만 상세를 연다.
/// 형식 밖 값은 상세 대신 탭 폴백으로 수렴한다(임의 문자열 실행·조회 금지).
final RegExp _kUuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// 유효한 UUID 면 트림값, 아니면 null.
String? validNotificationTargetId(String? raw) {
  final String v = raw?.trim() ?? '';
  if (v.isEmpty) return null;
  return _kUuidPattern.hasMatch(v) ? v : null;
}

/// 알림 딥링크 입력(파싱된 payload) — 불변 값 객체.
///
/// ★ 서버 payload 의 `link`/`url` 등 외부 경로 필드는 아예 담지 않는다 —
///   허용 목적지는 [resolveNotificationDeepLink] 의 화이트리스트 route 뿐
///   (임의 URL/scheme 실행 금지).
@immutable
class NotificationDeepLinkTarget {
  const NotificationDeepLinkTarget({
    required this.type,
    this.roomId,
    this.threadId,
    this.questionId,
    this.postId,
    this.shortformId,
    this.mentorId,
    this.eventId = '',
  });

  /// 정본 17종(목록 밖은 unknown — 이동 없음).
  final NotificationEventType type;

  /// 상세 딥링크용 내부 id(UUID 검증 후에만 상세를 연다).
  final String? roomId;
  final String? threadId;
  final String? questionId;
  final String? postId;
  final String? shortformId;
  final String? mentorId;

  /// 중복 수신 제거 키(notification_id 우선, event_key 폴백). 빈 문자열 = dedup 불가.
  final String eventId;
}

/// 딥링크 해결 결과 — 탭 이동 또는 검증된 상세 목적지(화이트리스트 고정).
/// stay/unknown 은 route 자체가 없다(null — 이동 없음).
sealed class NotificationDeepLinkRoute {
  const NotificationDeepLinkRoute();
}

/// 탭 이동만(정밀 id 없음·형식 불량 폴백 포함).
class NotificationTabRoute extends NotificationDeepLinkRoute {
  const NotificationTabRoute(this.tabIndex);
  final int tabIndex;
}

/// 질문방 상세 — roomId(+threadId 있으면 그 스레드 대화)로 연다.
class NotificationRoomRoute extends NotificationDeepLinkRoute {
  const NotificationRoomRoute({this.roomId, this.threadId});

  /// 검증된 UUID(없으면 threadId 로 방을 역추적한다).
  final String? roomId;
  final String? threadId;
}

/// 개별질문 상세.
class NotificationIqRoute extends NotificationDeepLinkRoute {
  const NotificationIqRoute(this.questionId);
  final String questionId;
}

/// 게시판 상세.
class NotificationBoardPostRoute extends NotificationDeepLinkRoute {
  const NotificationBoardPostRoute(this.postId);
  final String postId;
}

/// 숏폼 상세.
class NotificationShortformRoute extends NotificationDeepLinkRoute {
  const NotificationShortformRoute(this.shortformId);
  final String shortformId;
}

/// 멘토 상세.
class NotificationMentorRoute extends NotificationDeepLinkRoute {
  const NotificationMentorRoute(this.mentorId);
  final String mentorId;
}

/// 상세를 열 수 없을 때(상세 열기 미배선·대상 소실)의 탭 폴백.
int notificationRouteFallbackTab(NotificationDeepLinkRoute route) {
  switch (route) {
    case NotificationTabRoute(:final int tabIndex):
      return tabIndex;
    case NotificationRoomRoute():
      return AppTab.questionRoom;
    case NotificationIqRoute():
      return AppTab.individualQuestion;
    case NotificationBoardPostRoute():
    case NotificationShortformRoute():
      return AppTab.community;
    case NotificationMentorRoute():
      return AppTab.mentors;
  }
}

/// 딥링크 판정 정본(순수 — 테스트 대상): 타입+id → 허용 route.
///
/// 규칙:
/// - 목적지는 [notificationDestinationOf] 화이트리스트로만 결정 —
///   stay(맞춤의뢰류)·unknown 은 **null**(이동 없음, 맞춤의뢰 제외 유지).
/// - 상세는 **UUID 형식 검증을 통과한 id** 로만 연다. id 가 있는데 형식이
///   불량하면 해당 탭 폴백, id 자체가 없으면 알림 탭 폴백(내용 확인 유도).
/// - link/url 등 자유 경로 필드는 입력 모델에 존재하지 않는다(실행 금지).
NotificationDeepLinkRoute? resolveNotificationDeepLink(
    NotificationDeepLinkTarget target) {
  switch (notificationDestinationOf(target.type)) {
    case NotificationDestination.questionRoomTab:
      final String? roomId = validNotificationTargetId(target.roomId);
      final String? threadId = validNotificationTargetId(target.threadId);
      if (roomId != null || threadId != null) {
        return NotificationRoomRoute(roomId: roomId, threadId: threadId);
      }
      if (target.roomId == null && target.threadId == null) {
        return const NotificationTabRoute(AppTab.notifications);
      }
      return const NotificationTabRoute(AppTab.questionRoom);
    case NotificationDestination.individualQuestionTab:
      final String? questionId = validNotificationTargetId(target.questionId);
      if (questionId != null) return NotificationIqRoute(questionId);
      if (target.questionId == null) {
        return const NotificationTabRoute(AppTab.notifications);
      }
      return const NotificationTabRoute(AppTab.individualQuestion);
    case NotificationDestination.myPage:
      // 구독·멘토 공지류 — metadata 에 검증된 대상 id 가 있으면 그 상세로.
      final String? mentorId = validNotificationTargetId(target.mentorId);
      if (mentorId != null) return NotificationMentorRoute(mentorId);
      final String? postId = validNotificationTargetId(target.postId);
      if (postId != null) return NotificationBoardPostRoute(postId);
      final String? shortformId =
          validNotificationTargetId(target.shortformId);
      if (shortformId != null) return NotificationShortformRoute(shortformId);
      return const NotificationTabRoute(AppTab.myPage);
    case NotificationDestination.stay:
      return null; // 맞춤의뢰류·unknown — 이동 없음.
  }
}

/// 알림 탭 → 이동 판정·중복 제거·로그인 대기(pending) — 순수 로직(테스트 대상).
///
/// 규칙:
/// - 목적지는 [resolveNotificationDeepLink] 로만 결정(stay/unknown → 이동 없음).
/// - 상세 route 는 [openDetail] 이 배선된 경우에만 상세로 가고, 없으면 해당
///   탭 폴백([notificationRouteFallbackTab]) — 기존 탭 이동 계약과 호환.
/// - 같은 eventId 재전달(포그라운드+탭+콜드스타트 중복) → 최대 1회만 이동(LRU).
/// - 비로그인 상태의 탭 → pending 보관(TTL 15분), 로그인 성공 시 정확히 1회 이동.
///   로그아웃/계정 전환(forUserId 불일치) 시 폐기. 메모리 보관만(디스크 저장 없음).
/// - 알 수 없는 타입 → 이동 없음(stay). 타입은 알지만 필요한 id 부재 → 알림 탭 폴백.
class NotificationDeepLinkController {
  NotificationDeepLinkController({
    required void Function(int tabIndex) navigate,
    void Function(NotificationDeepLinkRoute route)? openDetail,
    DateTime Function()? now,
    Duration pendingTtl = const Duration(minutes: 15),
    int dedupCapacity = 32,
  })  : _navigate = navigate,
        _openDetail = openDetail,
        _now = now ?? DateTime.now,
        _pendingTtl = pendingTtl,
        _dedupCapacity = dedupCapacity;

  final void Function(int tabIndex) _navigate;

  /// 상세 열기 훅(선택) — 미배선이면 상세 route 도 탭 폴백으로 수렴한다.
  final void Function(NotificationDeepLinkRoute route)? _openDetail;

  final DateTime Function() _now;
  final Duration _pendingTtl;
  final int _dedupCapacity;

  /// 최근 처리한 eventId LRU(중복 이동 방지). 소량 고정 크기 — 메모리만.
  final Set<String> _seenEventIds = <String>{};

  String? _signedInUserId;

  /// 마지막으로 로그인했던 사용자(로그아웃 후에도 유지) — 이 디바이스로 배달된
  /// 푸시는 마지막 등록 계정 몫이므로, 비로그인 탭의 pending 을 이 사용자에게
  /// 귀속시킨다(다른 계정으로 로그인하면 폐기).
  String? _lastSignedInUserId;
  _PendingNavigation? _pending;

  bool get isSignedIn => _signedInUserId != null;

  @visibleForTesting
  bool get hasPendingForTest => _pending != null;

  /// 알림 탭 처리(포그라운드 탭·백그라운드 탭·콜드 스타트 공용 진입점).
  void handleTap(NotificationDeepLinkTarget target) {
    if (_isDuplicate(target.eventId)) return;

    final NotificationDeepLinkRoute? route =
        resolveNotificationDeepLink(target);
    if (route == null) return; // stay/unknown — 이동 없음.

    if (_signedInUserId == null) {
      // 비로그인 — 로그인 성공 후 1회 이동(TTL 내). 직전 로그인 사용자가 있으면
      // 그 사용자에게 귀속(계정 전환 시 폐기), 없으면 불명(null=누구든 허용).
      _pending = _PendingNavigation(
        route: route,
        forUserId: _lastSignedInUserId,
        createdAt: _now(),
      );
      return;
    }
    _dispatch(route);
  }

  /// 로그인 성공 훅 — pending 이 유효(TTL·사용자 일치)하면 정확히 1회 이동.
  void onSignedIn(String userId) {
    final _PendingNavigation? pending = _pending;
    _pending = null;
    _signedInUserId = userId;
    _lastSignedInUserId = userId;
    if (pending == null) return;
    if (pending.forUserId != null && pending.forUserId != userId) {
      return; // 다른 사용자의 대기 이동 — 폐기(계정 전환 안전).
    }
    if (_now().difference(pending.createdAt) > _pendingTtl) {
      return; // TTL 초과 — 오래된 이동 폐기.
    }
    _dispatch(pending.route);
  }

  /// 로그아웃/계정 전환 훅 — 이전 사용자의 대기 이동 폐기.
  void onSignedOut() {
    _signedInUserId = null;
    _pending = null;
  }

  void _dispatch(NotificationDeepLinkRoute route) {
    if (route is NotificationTabRoute) {
      _navigate(route.tabIndex);
      return;
    }
    final void Function(NotificationDeepLinkRoute route)? openDetail =
        _openDetail;
    if (openDetail != null) {
      openDetail(route);
    } else {
      _navigate(notificationRouteFallbackTab(route));
    }
  }

  /// eventId 중복 판정 + LRU 기록. 빈 eventId 는 dedup 불가(항상 새 이벤트).
  bool _isDuplicate(String eventId) {
    if (eventId.isEmpty) return false;
    if (_seenEventIds.contains(eventId)) return true;
    _seenEventIds.add(eventId);
    if (_seenEventIds.length > _dedupCapacity) {
      _seenEventIds.remove(_seenEventIds.first); // 가장 오래된 것부터 제거.
    }
    return false;
  }
}

/// 로그인 대기 이동(메모리 전용 — 디스크 저장 없음, 토큰류 값 미보관).
@immutable
class _PendingNavigation {
  const _PendingNavigation({
    required this.route,
    required this.forUserId,
    required this.createdAt,
  });

  final NotificationDeepLinkRoute route;

  /// 탭 시점에 알 수 있었던 대상 사용자(비로그인 탭은 null=불명).
  final String? forUserId;
  final DateTime createdAt;
}
