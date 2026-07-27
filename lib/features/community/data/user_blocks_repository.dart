import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

/// 차단 대상 결과(차단 액션의 결과 코드).
enum BlockResult { blocked, self, notLoggedIn, failed }

/// 차단 목록 표시용 행(id + 표시명). id(UUID)는 화면에 노출하지 않는다.
class BlockedUser {
  const BlockedUser({required this.userId, required this.displayName});
  final String userId;
  final String displayName;
}

/// 사용자 차단(user_blocks) 레포지토리 — 본인(blocker_id) 행만 다룬다(RLS 신뢰).
///
/// 테이블: `user_blocks(blocker_id, blocked_id)`. 조회/추가/삭제.
/// ★ 콘텐츠의 author_id 는 모델에 노출하지 않으므로, '이 글/댓글 작성자 차단'은
///   차단 시점에 콘텐츠 id 로 author_id 를 서버에서 조회해 넣는다(내부에만 사용).
/// ★ RLS/컬럼/네트워크 실패는 삼켜 흐름을 막지 않는다(빈 결과·failed 폴백).
class UserBlocksRepository {
  const UserBlocksRepository();

  static const String _table = 'user_blocks';

  SupabaseClient? get _client => SupabaseInit.clientOrNull;
  String? get _uid => _client?.auth.currentUser?.id;
  bool get isLoggedIn => _uid != null;

  /// 내가 차단한 사용자 id 집합(비로그인/실패 시 빈 집합).
  Future<Set<String>> myBlockedIds() async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return <String>{};
    try {
      final List<Map<String, dynamic>> rows =
          await c.from(_table).select('blocked_id').eq('blocker_id', uid);
      return <String>{
        for (final Map<String, dynamic> r in rows)
          if (r['blocked_id'] != null) r['blocked_id'] as String,
      };
    } catch (_) {
      return <String>{};
    }
  }

  /// 차단 목록(표시명 포함) — 차단 관리 화면용.
  Future<List<BlockedUser>> myBlockedUsers() async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return <BlockedUser>[];
    try {
      final List<Map<String, dynamic>> rows = await c
          .from(_table)
          .select('blocked_id')
          .eq('blocker_id', uid)
          .order('created_at', ascending: false);
      final List<String> ids = <String>[
        for (final Map<String, dynamic> r in rows)
          if (r['blocked_id'] != null) r['blocked_id'] as String,
      ];
      if (ids.isEmpty) return <BlockedUser>[];
      final Map<String, String> names = await _displayNames(c, ids);
      return <BlockedUser>[
        for (final String id in ids)
          BlockedUser(userId: id, displayName: names[id] ?? '사용자'),
      ];
    } catch (_) {
      return <BlockedUser>[];
    }
  }

  /// 표시명 조회(users 테이블 — nickname 우선). 실패/RLS 시 빈 맵(폴백 '사용자').
  Future<Map<String, String>> _displayNames(
      SupabaseClient c, List<String> ids) async {
    try {
      final List<Map<String, dynamic>> rows = await c
          .from('users')
          .select('id, nickname, full_name')
          .inFilter('id', ids);
      final Map<String, String> out = <String, String>{};
      for (final Map<String, dynamic> r in rows) {
        final String? id = r['id'] as String?;
        if (id == null) continue;
        final String nick = (r['nickname'] as String?)?.trim() ?? '';
        final String full = (r['full_name'] as String?)?.trim() ?? '';
        out[id] = nick.isNotEmpty ? nick : (full.isNotEmpty ? full : '사용자');
      }
      return out;
    } catch (_) {
      return <String, String>{};
    }
  }

  /// 차단 추가(중복은 성공으로 간주).
  Future<bool> block(String blockedId) async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return false;
    try {
      await c.from(_table).insert(<String, dynamic>{
        'blocker_id': uid,
        'blocked_id': blockedId,
      });
      return true;
    } catch (e) {
      final String m = e.toString().toLowerCase();
      return m.contains('duplicate') || m.contains('unique');
    }
  }

  /// 차단 해제.
  Future<bool> unblock(String blockedId) async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return false;
    try {
      await c
          .from(_table)
          .delete()
          .eq('blocker_id', uid)
          .eq('blocked_id', blockedId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 콘텐츠(글/댓글/숏폼) 작성자를 차단 — id 로 author_id 를 조회해 차단한다.
  /// [table] 예: 'community_posts' | 'comments'(게시판 댓글 — v16 정본) |
  /// 'community_comments'(숏폼 댓글) | 'shortform_posts'.
  Future<BlockResult> blockAuthorOf({
    required String table,
    required String contentId,
  }) async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return BlockResult.notLoggedIn;
    String? authorId;
    try {
      final Map<String, dynamic>? row = await c
          .from(table)
          .select('author_id')
          .eq('id', contentId)
          .maybeSingle();
      authorId = row?['author_id'] as String?;
    } catch (_) {
      return BlockResult.failed;
    }
    if (authorId == null) return BlockResult.failed;
    if (authorId == uid) return BlockResult.self; // 자기 자신은 차단 불가.
    final bool ok = await block(authorId);
    return ok ? BlockResult.blocked : BlockResult.failed;
  }
}
