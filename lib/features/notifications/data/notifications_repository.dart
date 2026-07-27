import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'app_notification.dart';

/// 키셋 커서(created_at DESC, id DESC). 고정 offset 페이징은 쓰지 않는다 —
/// 새 알림이 앞에 끼어들어도 중복/누락 없이 이어 읽기 위함.
///
/// ★ createdAtRaw 는 서버 created_at '원문 문자열' 그대로 보관한다(µs 정밀도
///   보존 — DateTime 왕복 변환 시 절삭돼 경계 행이 중복/누락될 수 있다).
class NotificationCursor {
  const NotificationCursor({required this.createdAtRaw, required this.id});

  /// 직전 페이지 마지막 행의 created_at 서버 원문.
  final String createdAtRaw;

  /// 직전 페이지 마지막 행의 id(동일 created_at 타이브레이커).
  final String id;
}

/// 알림 한 페이지(항목 + 다음 커서).
class NotificationsPage {
  const NotificationsPage({
    required this.items,
    required this.hasNext,
    this.next,
  });

  final List<AppNotification> items;
  final bool hasNext;

  /// 다음 페이지 조회용 커서(hasNext=false 면 null).
  final NotificationCursor? next;
}

/// 알림 조회·읽음 레포지토리(주입 가능 — 테스트에서 fake).
///
/// ★ 조회·읽음만. 알림 '생성'은 서버/푸시 몫(앱은 만들지 않음). 본인 알림만
///   (RLS) 다룬다. 환불·미지 타입은 숨기지 않는다. 단 CR 게이트 OFF(2026-07
///   출시)로 맞춤의뢰 2종([kGatedNotificationTypeCodes])만 **DB 쿼리 단계에서
///   exact type 제외**한다 — keyset cursor 가 필터 후 집합 위에서 동작하므로
///   페이지 크기·hasMore·경계 무결성이 유지된다(페이지 후 클라 제거 방식 금지).
abstract class NotificationsRepository {
  Future<NotificationsPage> fetch({NotificationCursor? after, int pageSize});
  Future<void> markRead(String id);

  /// 서버 RPC 로 본인 미읽음 전부 읽음 처리. 갱신 건수를 돌려준다(실패 시 throw).
  Future<int> markAllRead();
}

/// 원본 행(요청분 pageSize+1) → 페이지 조립(순수 로직 — 테스트 대상).
/// hasNext 는 초과분 존재 여부로 판단하고, 다음 커서는 '잘라낸 페이지의
/// 마지막 행' created_at 원문 + id 로 만든다.
NotificationsPage assembleNotificationsPage(
  List<Map<String, dynamic>> rows,
  int pageSize,
) {
  final bool hasNext = rows.length > pageSize;
  final List<Map<String, dynamic>> pageRows =
      hasNext ? rows.sublist(0, pageSize) : rows;
  NotificationCursor? next;
  if (hasNext && pageRows.isNotEmpty) {
    final Map<String, dynamic> last = pageRows.last;
    next = NotificationCursor(
      createdAtRaw: last['created_at'] as String,
      id: last['id'] as String,
    );
  }
  return NotificationsPage(
    items: pageRows.map(AppNotification.fromMap).toList(),
    hasNext: hasNext,
    next: next,
  );
}

/// 커서 이후(after) 행만 남기는 PostgREST or 필터 식.
/// (created_at, id) < (cursor.created_at, cursor.id) 의 키셋 표현.
String notificationsAfterFilter(NotificationCursor after) =>
    'created_at.lt.${after.createdAtRaw},'
    'and(created_at.eq.${after.createdAtRaw},id.lt.${after.id})';

/// Supabase 구현. RLS('본인 알림만')에 의존한다.
class SupabaseNotificationsRepository implements NotificationsRepository {
  const SupabaseNotificationsRepository();

  static const String _columns =
      'id, type, body, is_read, read, created_at, data, metadata';

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  /// CR 게이트 OFF — DB 단계 exact type 제외 목록(PostgREST `not.in`).
  static final String _gatedTypesInList =
      '(${kGatedNotificationTypeCodes.join(',')})';

  @override
  Future<NotificationsPage> fetch({
    NotificationCursor? after,
    int pageSize = 20,
  }) async {
    PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
        .from('notifications')
        .select(_columns)
        // 맞춤의뢰 2종 exact 제외(부분 문자열 아님). 필터가 커서보다 먼저 적용돼
        // 페이지 경계 중복·누락이 생기지 않는다.
        .not('type', 'in', _gatedTypesInList);
    if (after != null) {
      query = query.or(notificationsAfterFilter(after));
    }
    final List<Map<String, dynamic>> rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(pageSize + 1);
    return assembleNotificationsPage(rows, pageSize);
  }

  /// 현재 사용자 id. 읽음 처리의 본인 한정 필터에 쓴다(RLS 를 최종 방어로
  /// 두되 앱 계층에서도 본인 행만 대상 — user_id 미러 컬럼 기준 조회 허용).
  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<void> markRead(String id) async {
    final String? uid = _uid;
    if (uid == null) {
      throw const AppError('로그인이 필요해요.');
    }
    // 갱신된 행을 되돌려 받아 실제 성공(본인 행 존재)을 확인한다 —
    // 호출부는 성공 이후에만 UI 를 읽음으로 바꾼다.
    final List<Map<String, dynamic>> rows = await _client
        .from('notifications')
        .update(<String, dynamic>{
          'is_read': true,
          // 레거시 read 컬럼도 함께 갱신(웹 구버전 호환).
          'read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', uid)
        .select('id');
    if (rows.isEmpty) {
      throw const AppError('읽음 처리에 실패했어요.');
    }
  }

  @override
  Future<int> markAllRead() async {
    // 서버 RPC(mark_all_notifications_read) — 인자 없음, 갱신 건수 반환.
    final dynamic res = await _client.rpc('mark_all_notifications_read');
    if (res is int) return res;
    if (res is num) return res.toInt();
    return 0;
  }
}
