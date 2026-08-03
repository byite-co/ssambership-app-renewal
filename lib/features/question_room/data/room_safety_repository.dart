import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../community/data/user_blocks_repository.dart';

/// 안전 조치(신고/차단) 결과 코드. 서버 원문·SQL·코드는 절대 싣지 않는다.
enum SafetyOutcome {
  /// 성공(신고 접수 / 차단 완료 — 이미 차단된 상대도 성공).
  ok,

  /// 대상이 현재 사용자(자기 자신) — 실행하지 않았다.
  self,

  /// 세션 없음(비로그인 / 백엔드 미연결).
  notLoggedIn,

  /// 서버·네트워크 실패(fail-closed — 성공으로 표시하지 않는다).
  failed,
}

/// 질문방 안전 조치 포트. 화면은 이 포트만 알고, 테스트는 fake 를 주입한다.
abstract class RoomSafetyPort {
  /// 상대 사용자 신고 → `content_reports`.
  Future<SafetyOutcome> reportUser({
    required String targetUserId,
    required String reason,
    String? description,
  });

  /// 상대 사용자 차단 → `user_blocks`(이미 차단돼 있으면 멱등 성공).
  Future<SafetyOutcome> blockUser(String targetUserId);

  /// 내가 이 사용자를 차단해 두었는가(입장 시 composer 상태 판정용).
  Future<bool> isBlockedByMe(String targetUserId);
}

/// Supabase 구현.
///
/// ★ 신고 계약(실측 스키마 2026-08): `content_reports(reporter_id uuid,
///   target_type text NOT NULL, target_id uuid, reason text, description text,
///   status text NOT NULL)`. CHECK 는 `target_type` 공백 금지뿐이라 사용자 신고
///   target_type 값은 앱이 정한다 — 정본은 [userTargetType].
///   RLS `content_reports_insert_reporter`: `reporter_id = auth.uid()`.
/// ★ 차단은 커뮤니티와 **같은** `user_blocks` 테이블/레포를 쓴다 — 차단 해제는
///   기존 차단 관리 화면(`blocked_users_screen`)에서 그대로 동작한다.
/// ★ 실패는 사용자 문구로만 알린다(원문 비노출). 성공으로 위장하지 않는다.
class SupabaseRoomSafetyRepository implements RoomSafetyPort {
  const SupabaseRoomSafetyRepository(
      {this.blocks = const UserBlocksRepository()});

  final UserBlocksRepository blocks;

  /// `content_reports.target_type` — 사용자(상대방) 신고 정본 값.
  static const String userTargetType = 'user';

  static const String _reportsTable = 'content_reports';

  SupabaseClient? get _client => SupabaseInit.clientOrNull;
  String? get _uid => _client?.auth.currentUser?.id;

  @override
  Future<SafetyOutcome> reportUser({
    required String targetUserId,
    required String reason,
    String? description,
  }) async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return SafetyOutcome.notLoggedIn;
    if (targetUserId.isEmpty) return SafetyOutcome.failed;
    if (targetUserId == uid) return SafetyOutcome.self; // 자기 신고 금지.
    try {
      await c.from(_reportsTable).insert(<String, dynamic>{
        'reporter_id': uid,
        'target_type': userTargetType,
        'target_id': targetUserId,
        'reason': reason,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'status': 'pending',
      });
      return SafetyOutcome.ok;
    } catch (_) {
      return SafetyOutcome.failed; // fail-closed — 서버 오류 원문 비노출.
    }
  }

  @override
  Future<SafetyOutcome> blockUser(String targetUserId) async {
    final String? uid = _uid;
    if (_client == null || uid == null) return SafetyOutcome.notLoggedIn;
    if (targetUserId.isEmpty) return SafetyOutcome.failed;
    if (targetUserId == uid) return SafetyOutcome.self; // 자기 차단 금지.
    // 중복 차단은 레포가 멱등 성공(PK 23505)으로 돌려준다.
    final bool ok = await blocks.block(targetUserId);
    return ok ? SafetyOutcome.ok : SafetyOutcome.failed;
  }

  @override
  Future<bool> isBlockedByMe(String targetUserId) async {
    if (targetUserId.isEmpty) return false;
    final Set<String> ids = await blocks.myBlockedIds(); // 실패 시 빈 집합.
    return ids.contains(targetUserId);
  }
}
