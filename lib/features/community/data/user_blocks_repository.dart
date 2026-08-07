import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

/// 차단 대상 결과(차단 액션의 결과 코드).
enum BlockResult { blocked, self, notLoggedIn, failed }

/// insert 실패가 '이미 차단된 상대'인지 판정 — 멱등 성공으로 처리할 신호.
///
/// `user_blocks` PK 는 (blocker_id, blocked_id) 라 중복 차단은
/// unique_violation(23505)으로 떨어진다. 코드로 먼저 판정하고, 문구 매칭은
/// 드라이버/로케일 차이를 위한 폴백으로만 남긴다.
bool isAlreadyBlockedError(Object e) {
  if (e is PostgrestException && e.code == '23505') return true;
  final String m = e.toString().toLowerCase();
  return m.contains('duplicate') || m.contains('unique');
}

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

  // ── 차단 목록 캐시(N15) ──
  // 커뮤니티 목록·댓글·질문방 입장이 조회마다 user_blocks 를 재조회하던 것을
  // 사용자별 짧은 TTL 캐시 + single-flight 로 줄인다. 차단/해제 성공 시 즉시
  // 무효화하므로 사용자 가시 지연은 TTL 이 아니라 0 이고, 계정 전환은 uid
  // 키 불일치로 자연 무효화된다. 실패 결과(빈 집합 폴백)는 캐시하지 않는다.
  static String? _cacheUid;
  static Set<String>? _cachedIds;
  static DateTime? _cachedAt;
  static Future<Set<String>>? _inFlight;
  static const Duration _cacheTtl = Duration(seconds: 30);

  /// 캐시 무효화 — 차단/해제 성공 직후, 그리고 테스트에서 호출한다.
  static void invalidateBlockedIdsCache() {
    _cacheUid = null;
    _cachedIds = null;
    _cachedAt = null;
    _inFlight = null;
  }

  /// 내가 차단한 사용자 id 집합(비로그인/실패 시 빈 집합).
  Future<Set<String>> myBlockedIds() {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) {
      return Future<Set<String>>.value(<String>{});
    }
    final DateTime now = DateTime.now();
    if (_cacheUid == uid &&
        _cachedIds != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheTtl) {
      return Future<Set<String>>.value(<String>{..._cachedIds!});
    }
    final Future<Set<String>>? inFlight = _inFlight;
    if (inFlight != null && _cacheUid == uid) return inFlight;
    _cacheUid = uid;
    final Future<Set<String>> load = _fetchBlockedIds(c, uid).then(
      (Set<String> ids) {
        if (_cacheUid == uid) {
          _cachedIds = ids;
          _cachedAt = DateTime.now();
        }
        return <String>{...ids};
      },
    ).whenComplete(() {
      if (_cacheUid == uid) _inFlight = null;
    });
    _inFlight = load;
    return load;
  }

  Future<Set<String>> _fetchBlockedIds(SupabaseClient c, String uid) async {
    try {
      final List<Map<String, dynamic>> rows =
          await c.from(_table).select('blocked_id').eq('blocker_id', uid);
      return <String>{
        for (final Map<String, dynamic> r in rows)
          if (r['blocked_id'] != null) r['blocked_id'] as String,
      };
    } catch (_) {
      // 실패 폴백은 캐시하지 않는다 — 다음 호출이 다시 시도한다.
      if (_cacheUid == uid) {
        _cachedIds = null;
        _cachedAt = null;
      }
      return <String>{};
    }
  }

  /// 차단 목록(표시명 포함) — 차단 관리 화면용.
  ///
  /// [QA-C7] 종전에는 user_blocks 조회 후 users 를 직접 읽어 닉네임을 붙였는데,
  /// public.users 의 SELECT 정책이 **본인 + admin** 뿐이라 타인 행이 0건으로
  /// 돌아왔다 — 그래서 화면에 전부 '사용자'로만 보였다. 앱 결함이 아니라 서버가
  /// 표시명을 내줄 경로가 없었다.
  ///
  /// 서버가 정의자 RPC `public.my_blocked_users()` 를 제공한다(웹 migration
  /// 20260807020000). 인자가 없어 타인 목록을 물을 수 없고, 반환은
  /// blocked_id · nickname · created_at 뿐이다.
  ///
  /// RPC 가 아직 배포되지 않은 서버(구버전)에서는 종전 경로로 물러난다 —
  /// 이름은 '사용자' 폴백이 되지만 **차단 목록 자체는 보여야** 해제할 수 있다.
  Future<List<BlockedUser>> myBlockedUsers() async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return <BlockedUser>[];
    final List<BlockedUser>? viaRpc = await _blockedUsersViaRpc(c);
    if (viaRpc != null) return viaRpc;
    return _blockedUsersLegacy(c, uid);
  }

  /// 정본 경로 — 서버 RPC. 호출 자체가 실패하면 null 을 돌려 폴백을 태운다
  /// (빈 목록과 '조회 실패'를 구분한다 — 빈 목록도 정상 응답이다).
  Future<List<BlockedUser>?> _blockedUsersViaRpc(SupabaseClient c) async {
    try {
      final Object? res = await c.rpc('my_blocked_users');
      if (res is! List) return null;
      final List<BlockedUser> out = <BlockedUser>[];
      for (final Object? row in res) {
        if (row is! Map) continue;
        final String? id = row['blocked_id'] as String?;
        if (id == null || id.isEmpty) continue;
        final String nick = (row['nickname'] as String?)?.trim() ?? '';
        out.add(BlockedUser(
          userId: id,
          displayName: nick.isEmpty ? '사용자' : nick,
        ));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// 구서버 폴백 — 차단 id 만 읽어 목록을 만든다(이름은 '사용자').
  Future<List<BlockedUser>> _blockedUsersLegacy(
      SupabaseClient c, String uid) async {
    try {
      final List<Map<String, dynamic>> rows = await c
          .from(_table)
          .select('blocked_id')
          .eq('blocker_id', uid)
          .order('created_at', ascending: false);
      return <BlockedUser>[
        for (final Map<String, dynamic> r in rows)
          if (r['blocked_id'] != null)
            BlockedUser(userId: r['blocked_id'] as String, displayName: '사용자'),
      ];
    } catch (_) {
      return <BlockedUser>[];
    }
  }

  /// 차단 추가(중복은 성공으로 간주 = 멱등).
  ///
  /// ★ `user_blocks` PK 는 (blocker_id, blocked_id) 라 이미 차단한 상대를 다시
  ///   차단하면 unique_violation(23505)이 난다 — 코드로 먼저 판정하고,
  ///   문구 매칭은 로케일/드라이버 차이를 위한 폴백으로만 남긴다.
  /// ★ 자기 자신은 DB CHECK(blocker_id <> blocked_id)가 막지만, 호출부에서
  ///   먼저 걸러 사용자에게 명확한 문구를 보여준다.
  Future<bool> block(String blockedId) async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return false;
    if (blockedId.isEmpty || blockedId == uid) return false;
    try {
      await c.from(_table).insert(<String, dynamic>{
        'blocker_id': uid,
        'blocked_id': blockedId,
      });
      invalidateBlockedIdsCache(); // N15: 차단 즉시 목록 캐시 무효화.
      return true;
    } catch (e) {
      final bool already = isAlreadyBlockedError(e);
      if (already) invalidateBlockedIdsCache();
      return already;
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
      invalidateBlockedIdsCache(); // N15: 해제 즉시 목록 캐시 무효화.
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 이미 알고 있는 작성자 id 를 차단(자기 자신 차단 불가 판정 포함).
  ///
  /// 게시판 글처럼 화면이 이미 정본 뷰 행에서 author_id 를 갖고 있는 경우
  /// 추가 조회 없이 이 경로를 쓴다(C10 — community_posts 베이스 테이블
  /// 접근 0건 계약을 코드로도 참이 되게 한다).
  Future<BlockResult> blockAuthor(String authorId) async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return BlockResult.notLoggedIn;
    if (authorId == uid) return BlockResult.self; // 자기 자신은 차단 불가.
    final bool ok = await block(authorId);
    return ok ? BlockResult.blocked : BlockResult.failed;
  }

  /// 콘텐츠(댓글/숏폼) 작성자를 차단 — id 로 author_id 를 조회해 차단한다.
  /// [table] 예: 'comments'(게시판 댓글 — v16 정본) |
  /// 'community_comments'(숏폼 댓글) | 'shortform_posts'.
  /// ★ 'community_posts' 는 금지(베이스 접근 0건 계약) — 게시판 글은
  ///   뷰 행의 author_id 로 [blockAuthor] 를 쓴다.
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
    return blockAuthor(authorId);
  }
}
