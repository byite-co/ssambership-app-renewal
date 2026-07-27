import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';

/// 찜 목록 조회 결과 — 실패를 빈 집합으로 위장하지 않는다(빈 찜 ≠ 조회 실패).
sealed class MentorFavoritesLoad {
  const MentorFavoritesLoad();
}

/// 비로그인(또는 백엔드 미구성) — 찜 기능 비활성, 로그인 유도 대상.
class MentorFavoritesLoggedOut extends MentorFavoritesLoad {
  const MentorFavoritesLoggedOut();
}

/// 조회 성공. [ids] 가 비어 있으면 '아직 찜한 멘토가 없어요'(empty) 상태다.
class MentorFavoritesLoaded extends MentorFavoritesLoad {
  const MentorFavoritesLoaded(this.ids);
  final Set<String> ids;
}

/// 조회 실패 — 화면은 빈 목록이 아니라 오류·재시도를 보여야 한다.
class MentorFavoritesLoadError extends MentorFavoritesLoad {
  const MentorFavoritesLoadError();
}

/// 멘토 찜(favorites) 레포지토리 — 본인(user_id) 행만 다룬다(RLS 신뢰).
///
/// 테이블: `favorites(user_id, mentor_id)`. 조회/추가/삭제만.
/// ★ 조회 실패는 [MentorFavoritesLoadError] 로 드러낸다(빈 집합 위장 금지).
///   추가/삭제 실패는 false 폴백(호출자가 낙관 토글을 원복).
class MentorFavoritesRepository {
  const MentorFavoritesRepository();

  static const String _table = 'favorites';

  SupabaseClient? get _client => SupabaseInit.clientOrNull;
  String? get _uid => _client?.auth.currentUser?.id;

  /// 로그인 여부(비로그인 시 찜 대신 로그인 유도).
  bool get isLoggedIn => _uid != null;

  /// 내가 찜한 멘토 id 조회 — 비로그인/성공/실패를 구분해 반환한다.
  Future<MentorFavoritesLoad> loadMyFavoriteMentorIds() async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return const MentorFavoritesLoggedOut();
    try {
      final List<Map<String, dynamic>> rows =
          await c.from(_table).select('mentor_id').eq('user_id', uid);
      return MentorFavoritesLoaded(<String>{
        for (final Map<String, dynamic> r in rows)
          if (r['mentor_id'] != null) r['mentor_id'] as String,
      });
    } catch (_) {
      return const MentorFavoritesLoadError();
    }
  }

  /// 찜 추가. 성공/이미 찜(중복)이면 true. 비로그인/실패면 false.
  Future<bool> add(String mentorId) async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return false;
    try {
      await c.from(_table).insert(<String, dynamic>{
        'user_id': uid,
        'mentor_id': mentorId,
      });
      return true;
    } catch (e) {
      // 유니크 위반(이미 찜)은 성공으로 간주.
      final String m = e.toString().toLowerCase();
      return m.contains('duplicate') || m.contains('unique');
    }
  }

  /// 찜 해제. 성공/비로그인 아님이면 true, 실패면 false.
  Future<bool> remove(String mentorId) async {
    final SupabaseClient? c = _client;
    final String? uid = _uid;
    if (c == null || uid == null) return false;
    try {
      await c
          .from(_table)
          .delete()
          .eq('user_id', uid)
          .eq('mentor_id', mentorId);
      return true;
    } catch (_) {
      return false;
    }
  }
}
