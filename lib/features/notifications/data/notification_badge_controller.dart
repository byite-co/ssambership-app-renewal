import 'package:flutter/foundation.dart';

import 'notifications_repository.dart';

/// 하단 탭 알림 배지 라벨 — **서버 개수만**으로 결정한다(로컬 목록 계산 금지).
/// null(미확인)·0 → 배지 숨김(null 반환), 1~99 → 그대로, 100 이상 → '99+'.
String? notificationBadgeLabel(int? count) {
  if (count == null || count <= 0) return null;
  if (count >= 100) return '99+';
  return '$count';
}

/// 알림 배지 상태 컨트롤러(앱 전역 1개) — 소스는 서버 RPC
/// `notification_unread_count_self` 하나뿐이다.
///
/// - [refresh] : 서버 재조회(로그인 후·실시간 수신·화면 진입·복귀·재연결).
///   실패는 조용히 무시하고 마지막 값을 유지한다(배지는 비핵심 표면).
/// - 단건 읽음은 **낙관 감소**([onMarkReadOptimistic]) 후 실패 시 롤백
///   ([rollbackMarkRead]) — 모두읽음 성공 후에는 [refresh] 로 0 을 재확인한다.
/// - [clear] : 로그아웃/계정 전환 — 이전 사용자 값을 폐기한다(배지 숨김).
class NotificationBadgeController {
  NotificationBadgeController({NotificationsRepository? repository})
      : _repository = repository ?? const SupabaseNotificationsRepository();

  /// 앱 전역 공유 인스턴스(HomeShell 배지 ↔ 알림 화면이 함께 쓴다).
  static final NotificationBadgeController instance =
      NotificationBadgeController();

  final NotificationsRepository _repository;

  /// 서버 미읽음 개수. null = 아직 확인 전(배지 숨김).
  final ValueNotifier<int?> count = ValueNotifier<int?>(null);

  /// 늦게 도착한 이전 조회 응답 폐기용 세대 토큰.
  int _generation = 0;

  /// N24: 버스트 코얼레싱 — 실시간 INSERT 가 연달아 와도 진행 중 조회 1개 +
  /// 종료 후 후행 1개로 수렴한다(수신 건수만큼 RPC 를 쏘지 않는다).
  bool _refreshing = false;
  bool _refreshQueued = false;

  /// 서버 정본 재조회. 실패는 조용히 무시(마지막 값 유지 — 값 날조 금지).
  /// 진행 중이면 후행 1회로 합쳐진다(N24) — 호출 즉시 반환될 수 있다.
  Future<void> refresh() async {
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshQueued = false;
        final int gen = ++_generation;
        try {
          final int value = await _repository.unreadCount();
          if (gen == _generation) count.value = value;
        } catch (_) {
          // 실패 — 기존 값 유지. 배지가 목록 이용을 막지 않는다.
        }
      } while (_refreshQueued);
    } finally {
      _refreshing = false;
    }
  }

  /// 단건 읽음 낙관 감소(0 미만 금지). 서버 확인값이 없으면 아무것도 안 한다.
  void onMarkReadOptimistic() {
    final int? v = count.value;
    if (v == null || v <= 0) return;
    count.value = v - 1;
  }

  /// 단건 읽음 실패 롤백(낙관 감소 원복).
  void rollbackMarkRead() {
    final int? v = count.value;
    if (v == null) return;
    count.value = v + 1;
  }

  /// 로그아웃/계정 전환 — 이전 사용자 개수 폐기(다음 로그인에서 재조회).
  void clear() {
    _generation++;
    count.value = null;
  }
}
