import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';

/// 댓글 원천 테이블 접근 통로(테스트 seam).
///
/// v16 정본 전환: 게시판 댓글은 정본 `comments` 테이블, 숏폼 댓글은 기존
/// `community_comments(post_type='shortform')` 를 계속 쓴다(서버 양방향 브리지 운영 중).
/// 레포지토리는 테이블·필터·페이로드 '결정'만 하고 실제 접근은 이 통로 하나로
/// 지나가므로, 테스트는 손수 만든 기록형 가짜로 계약(테이블명·페이로드)을 검증한다
/// (규약: mocktail 등 목 프레임워크 금지 — test/community/fakes.dart 참고).
class CommentsGateway {
  const CommentsGateway();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  /// 현재 로그인 사용자 id(비로그인/미연결이면 null) — 댓글 작성 author_id 용.
  String? get currentUserId => SupabaseInit.clientOrNull?.auth.currentUser?.id;

  /// [table] 에서 [filters](모두 eq 조건)로 조회, created_at 오름차순(대화순).
  /// [limit] 지정 시 [offset]부터 그만큼만(페이징).
  Future<List<Map<String, dynamic>>> selectComments({
    required String table,
    required Map<String, Object> filters,
    int? limit,
    int offset = 0,
  }) async {
    dynamic q = _client.from(table).select('*');
    for (final MapEntry<String, Object> f in filters.entries) {
      q = q.eq(f.key, f.value);
    }
    q = q.order('created_at', ascending: true);
    if (limit != null) q = q.range(offset, offset + limit - 1);
    final List<Map<String, dynamic>> rows = await q;
    return rows;
  }

  /// [table] 에 [values] 를 INSERT 하고 생성된 행을 돌려준다.
  Future<Map<String, dynamic>> insertComment({
    required String table,
    required Map<String, dynamic> values,
  }) {
    return _client.from(table).insert(values).select().single();
  }
}
