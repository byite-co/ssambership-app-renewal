import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';

/// 알림 설정 저장·로드 — 정본 테이블 `notification_settings` 대상.
///
/// 서버 계약(스냅샷 4.1 '설정'):
/// - `notification_settings(user_id PK, push_enabled bool, groups jsonb, updated_at)`,
///   RLS select_own/modify_own — 본인 행 SELECT/UPSERT 가능.
/// - 발송 판정(notification_delivery_allowed): 행 없음 → 허용(ON),
///   `push_enabled AND coalesce(groups->>group, true)` — 그룹 키 부재도 허용(ON).
/// - (구) `users.notification_enabled` 컬럼 방식은 폐기 — 여기서 더 이상 쓰지 않는다.
///
/// ★ 실패를 기본값으로 위장하지 않는다: 조회/저장 오류는 AppError 로 올려
///   화면이 '다시 시도' 상태를 보여줄 수 있게 한다(조용한 ON 위장 금지).

/// 알림 그룹 정본(notification_event_group 과 정렬). 키는 이 5개로 한정.
abstract final class NotificationGroups {
  /// 서버 그룹 키(순서 = 화면 노출 순서).
  static const List<String> keys = <String>[
    'qna',
    'order',
    'subscription',
    'refund',
    'system',
  ];

  /// 화면용 한글 라벨(영문 코드 비노출 규약).
  /// 'order' 키는 서버 설정 호환을 위해 유지하되, CR 게이트 OFF(2026-07 출시)로
  /// 앱이 맞춤의뢰 알림을 노출하지 않으므로 라벨은 '개별질문 알림'으로 표기한다.
  static const Map<String, String> labels = <String, String>{
    'qna': '질문방 알림',
    'order': '개별질문 알림',
    'subscription': '구독·결제 알림',
    'refund': '환불 알림',
    'system': '기타 알림',
  };

  /// 키 → 라벨(모르는 키 방어 — 정본 5키만 쓰므로 실사용에선 항상 존재).
  static String labelOf(String key) => labels[key] ?? key;
}

/// 알림 설정 값 객체. 행/키 부재 = ON 의미론을 그대로 담는다.
class NotificationSettings {
  const NotificationSettings({
    this.pushEnabled = true,
    this.groups = const <String, bool>{},
  });

  /// 마스터 스위치. false 면 서버가 전 그룹 발송을 막는다.
  final bool pushEnabled;

  /// 그룹별 on/off. 키 부재 = ON(서버 coalesce(true) 와 동일).
  final Map<String, bool> groups;

  /// 서버 의미론 그대로: 키 없으면 허용(ON).
  bool groupEnabled(String key) => groups[key] ?? true;

  NotificationSettings copyWith({
    bool? pushEnabled,
    Map<String, bool>? groups,
  }) {
    return NotificationSettings(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      groups: groups ?? this.groups,
    );
  }

  /// 한 그룹만 바꾼 사본.
  NotificationSettings withGroup(String key, bool enabled) {
    return copyWith(groups: <String, bool>{...groups, key: enabled});
  }
}

/// 설정 저장소 포트 — 화면은 이 추상에만 의존(테스트 페이크 주입).
abstract class NotificationSettingsPort {
  /// 저장된 설정 로드. 행 없음 → 기본값(전부 ON). 실패 시 AppError(기본값 위장 금지).
  Future<NotificationSettings> load();

  /// 본인 행 upsert. 실패 시 AppError(성공 위장 금지).
  Future<void> save(NotificationSettings settings);
}

/// 백엔드 행 접근 포트 — Supabase 쿼리를 좁은 경계로 감싸 레포 로직을 페이크로 검증.
abstract class NotificationSettingsBackend {
  /// 로그인 사용자 id(비로그인/미초기화면 null).
  String? get currentUserId;

  /// 본인 행 1개 조회(없으면 null). 쿼리 실패는 예외 그대로.
  Future<Map<String, dynamic>?> fetchRow(String userId);

  /// 본인 행 upsert. 실패는 예외 그대로.
  Future<void> upsertRow(Map<String, dynamic> row);
}

/// 실제 Supabase 백엔드(`notification_settings` 테이블).
class SupabaseNotificationSettingsBackend
    implements NotificationSettingsBackend {
  const SupabaseNotificationSettingsBackend();

  static const String table = 'notification_settings';

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) throw const AppError('백엔드에 연결되어 있지 않아요.');
    return c;
  }

  @override
  String? get currentUserId => SupabaseInit.clientOrNull?.auth.currentUser?.id;

  @override
  Future<Map<String, dynamic>?> fetchRow(String userId) {
    return _client
        .from(table)
        .select('push_enabled, groups')
        .eq('user_id', userId)
        .maybeSingle();
  }

  @override
  Future<void> upsertRow(Map<String, dynamic> row) async {
    await _client.from(table).upsert(row, onConflict: 'user_id');
  }
}

/// 레포 구현 — 파싱·기본값·정직한 실패 전파를 담당.
class NotificationSettingsRepository implements NotificationSettingsPort {
  const NotificationSettingsRepository({
    NotificationSettingsBackend backend =
        const SupabaseNotificationSettingsBackend(),
  }) : _backend = backend;

  final NotificationSettingsBackend _backend;

  String get _uid {
    final String? id = _backend.currentUserId;
    if (id == null) throw const AppError('로그인이 필요해요.');
    return id;
  }

  @override
  Future<NotificationSettings> load() async {
    final String uid = _uid;
    final Map<String, dynamic>? row;
    try {
      row = await _backend.fetchRow(uid);
    } on AppError {
      rethrow;
    } catch (e) {
      // ★ 실패를 기본값(전부 ON)으로 위장하지 않는다 — 화면이 재시도를 안내.
      throw AppError('알림 설정을 불러오지 못했어요.', cause: e);
    }
    if (row == null) return const NotificationSettings(); // 행 없음 = 전부 ON.
    return _parse(row);
  }

  @override
  Future<void> save(NotificationSettings settings) async {
    final String uid = _uid;
    // 정본 5키만 저장(그 외 키는 서버 판정에 없으므로 버림).
    final Map<String, bool> groups = <String, bool>{
      for (final MapEntry<String, bool> e in settings.groups.entries)
        if (NotificationGroups.keys.contains(e.key)) e.key: e.value,
    };
    try {
      await _backend.upsertRow(<String, dynamic>{
        'user_id': uid,
        'push_enabled': settings.pushEnabled,
        'groups': groups,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on AppError {
      rethrow;
    } catch (e) {
      throw AppError('알림 설정을 저장하지 못했어요.', cause: e);
    }
  }

  /// 행 → 값 객체. 알 수 없는 키/비 bool 값은 버린다(키 없음 = ON 유지).
  NotificationSettings _parse(Map<String, dynamic> row) {
    final Object? enabled = row['push_enabled'];
    final Object? rawGroups = row['groups'];
    final Map<String, bool> groups = <String, bool>{};
    if (rawGroups is Map) {
      for (final MapEntry<dynamic, dynamic> e in rawGroups.entries) {
        final Object? k = e.key;
        final Object? v = e.value;
        if (k is String && v is bool && NotificationGroups.keys.contains(k)) {
          groups[k] = v;
        }
      }
    }
    return NotificationSettings(
      pushEnabled: enabled is bool ? enabled : true,
      groups: groups,
    );
  }
}
