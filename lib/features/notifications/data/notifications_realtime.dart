import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

/// 알림 실시간 포트 — 본인 수신자 필터(recipient_user_id)로 INSERT 이벤트를
/// 콜백으로 전달한다(thread_realtime 과 동일 구조).
///
/// 화면(알림 센터)이 주입받아 구독한다. 테스트에서는 fake 를 주입해 실제
/// 네트워크 없이 이벤트 방출을 흉내낸다. ★ 실시간은 보조 채널일 뿐 — 목록·
/// 배지의 정본은 언제나 서버 재조회(fetch / unreadCount)다.
abstract class NotificationsRealtimePort {
  /// 구독 시작. [onInsert] 는 새 알림 행(raw map)마다 호출된다.
  /// [onReconnected] 는 끊겼다 다시 붙었을 때 1회 — 부모가 첫 페이지 + 개수를
  /// 재조회해 공백을 메운다.
  void start({
    required void Function(Map<String, dynamic> row) onInsert,
    void Function()? onReconnected,
  });

  /// 구독 정리(누수 금지). 화면 dispose·로그아웃·계정 전환에서 호출.
  Future<void> dispose();
}

/// Supabase Realtime 구현(postgres_changes).
///
/// ★ 인프라 의존: notifications 가 `supabase_realtime` publication 에 포함돼
///   있어야 이벤트가 도착한다(계약 8). 미포함이면 콜백이 오지 않으며, 화면은
///   진입/복귀/당겨서 새로고침 재조회로 계속 동작한다.
class SupabaseNotificationsRealtime implements NotificationsRealtimePort {
  SupabaseNotificationsRealtime(this.userId);

  /// 수신자(auth uid) — 채널명·필터에 쓴다. 계정 전환 시 반드시 dispose 후
  /// 새 uid 로 재구독한다(이전 사용자 이벤트 오배달 방지).
  final String userId;

  RealtimeChannel? _channel;
  bool _subscribedOnce = false;

  @override
  void start({
    required void Function(Map<String, dynamic> row) onInsert,
    void Function()? onReconnected,
  }) {
    final SupabaseClient? client = SupabaseInit.clientOrNull;
    if (client == null) return; // 백엔드 미연결 → 조용히 무시(폴백만 동작).

    final RealtimeChannel channel = client.channel('notifications_$userId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_user_id',
        value: userId,
      ),
      callback: (PostgresChangePayload payload) {
        try {
          onInsert(payload.newRecord);
        } catch (_) {
          // 파싱 실패는 무시(다음 재조회가 보완).
        }
      },
    );

    channel.subscribe((RealtimeSubscribeStatus status, Object? error) {
      if (status != RealtimeSubscribeStatus.subscribed) return;
      if (_subscribedOnce) {
        onReconnected?.call();
      }
      _subscribedOnce = true;
    });
    _channel = channel;
  }

  @override
  Future<void> dispose() async {
    final RealtimeChannel? ch = _channel;
    _channel = null;
    if (ch != null) {
      await SupabaseInit.clientOrNull?.removeChannel(ch);
    }
  }
}
