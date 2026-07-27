import 'package:flutter/foundation.dart';

import '../../app/app_tabs.dart';
import '../../features/notifications/data/notification_types.dart';

/// 알림 딥링크 입력(파싱된 payload) — 불변 값 객체.
///
/// ★ 서버 payload 의 `link`/`url` 등 외부 경로 필드는 아예 담지 않는다 —
///   허용 목적지는 notificationDestinationOf 의 탭뿐(임의 URL/scheme 실행 금지).
@immutable
class NotificationDeepLinkTarget {
  const NotificationDeepLinkTarget({
    required this.type,
    this.roomId,
    this.threadId,
    this.questionId,
    this.eventId = '',
  });

  /// 정본 17종(목록 밖은 unknown — 이동 없음).
  final NotificationEventType type;

  /// 정밀 딥링크 후속용 내부 id(현 라우터는 탭 이동만 — 존재 여부만 판정에 사용).
  final String? roomId;
  final String? threadId;
  final String? questionId;

  /// 중복 수신 제거 키(notification_id 우선, event_key 폴백). 빈 문자열 = dedup 불가.
  final String eventId;
}

/// 알림 탭 → 탭 이동 판정·중복 제거·로그인 대기(pending) — 순수 로직(테스트 대상).
///
/// 규칙:
/// - 목적지는 notificationDestinationOf 로만 결정(stay/unknown → 이동 없음).
/// - 같은 eventId 재전달(포그라운드+탭+콜드스타트 중복) → 최대 1회만 이동(LRU).
/// - 비로그인 상태의 탭 → pending 보관(TTL 15분), 로그인 성공 시 정확히 1회 이동.
///   로그아웃/계정 전환(forUserId 불일치) 시 폐기. 메모리 보관만(디스크 저장 없음).
/// - 알 수 없는 타입 → 이동 없음(stay). 타입은 알지만 필요한 id 부재 → 알림 탭 폴백.
class NotificationDeepLinkController {
  NotificationDeepLinkController({
    required void Function(int tabIndex) navigate,
    DateTime Function()? now,
    Duration pendingTtl = const Duration(minutes: 15),
    int dedupCapacity = 32,
  })  : _navigate = navigate,
        _now = now ?? DateTime.now,
        _pendingTtl = pendingTtl,
        _dedupCapacity = dedupCapacity;

  final void Function(int tabIndex) _navigate;
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

    final int? tab = _resolveTab(target);
    if (tab == null) return; // stay/unknown — 이동 없음.

    if (_signedInUserId == null) {
      // 비로그인 — 로그인 성공 후 1회 이동(TTL 내). 직전 로그인 사용자가 있으면
      // 그 사용자에게 귀속(계정 전환 시 폐기), 없으면 불명(null=누구든 허용).
      _pending = _PendingNavigation(
        tabIndex: tab,
        forUserId: _lastSignedInUserId,
        createdAt: _now(),
      );
      return;
    }
    _navigate(tab);
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
    _navigate(pending.tabIndex);
  }

  /// 로그아웃/계정 전환 훅 — 이전 사용자의 대기 이동 폐기.
  void onSignedOut() {
    _signedInUserId = null;
    _pending = null;
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

  /// 목적지 판정 — 허용 목적지(notificationDestinationOf)만. null = 이동 없음.
  int? _resolveTab(NotificationDeepLinkTarget target) {
    switch (notificationDestinationOf(target.type)) {
      case NotificationDestination.questionRoomTab:
        // 대상 방/스레드 id 가 없으면 알림 탭 폴백(내용 확인 유도).
        if (target.roomId == null && target.threadId == null) {
          return AppTab.notifications;
        }
        return AppTab.questionRoom;
      case NotificationDestination.individualQuestionTab:
        if (target.questionId == null) return AppTab.notifications;
        return AppTab.individualQuestion;
      case NotificationDestination.myPage:
        return AppTab.myPage;
      case NotificationDestination.stay:
        return null; // unknown 포함 — 이동 없음.
    }
  }
}

/// 로그인 대기 이동(메모리 전용 — 디스크 저장 없음, 토큰류 값 미보관).
@immutable
class _PendingNavigation {
  const _PendingNavigation({
    required this.tabIndex,
    required this.forUserId,
    required this.createdAt,
  });

  final int tabIndex;

  /// 탭 시점에 알 수 있었던 대상 사용자(비로그인 탭은 null=불명).
  final String? forUserId;
  final DateTime createdAt;
}
