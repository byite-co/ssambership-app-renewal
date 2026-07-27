import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/entitlement/subscription_summary.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'mentor_models.dart';

/// 멘토 찾기(공개·열람 전용) 레포지토리.
///
/// 모두 공개 조회 가능한 소스만 사용한다:
/// - `mentor_directory_list_v2(p_limit)` : 공개 멘토 목록(id·표시명·상태·가입일)
/// - `mentor_profiles_for_directory_v2(p_ids)` : 공개 프로필(학교·과목·소개·인증)
/// - `mentor_plans` (is_active=true) : 요금제(가격 '표시'만)
/// - `get_mentor_avg_response_hours(p_mentor_id)` : 평균 답변시간(없으면 null)
/// 구독 여부는 본인 행만 보이는 subscriptions 를 [SubscriptionReader] 로 읽는다.
class MentorDirectoryRepository {
  const MentorDirectoryRepository();

  /// 디렉터리 RPC 의 검증된 최대 범위(웹과 동일). 서버 함수 상한도 200(스테이징 실측
  /// 2026-07: `least(coalesce(p_limit,80),200)`). 검색·필터를 전체 집합에 적용하려면
  /// 이 범위를 한 번에 로드한다.
  static const int directoryMaxLimit = 200;

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  /// 공개 멘토 목록. 디렉터리 → 프로필 → 활성 요금제를 묶어 한 행으로 만든다.
  Future<List<MentorListItem>> list({int limit = 20}) async {
    final dynamic dirRes = await _client.rpc(
      'mentor_directory_list_v2',
      params: <String, dynamic>{'p_limit': limit},
    );
    final List<MentorListItem> entries = <MentorListItem>[];
    if (dirRes is List) {
      for (final Object? row in dirRes) {
        if (row is Map<String, dynamic>) {
          entries.add(MentorListItem.fromDirectoryMap(row));
        }
      }
    }
    if (entries.isEmpty) return <MentorListItem>[];

    final List<String> ids =
        entries.map((MentorListItem e) => e.id).toList(growable: false);
    final Map<String, MentorProfileInfo> profiles = await _profiles(ids);
    final Map<String, List<MentorPlan>> plans = await _activePlans(ids);
    // 정렬(별점·리뷰순)용 공개 리뷰 집계 — 목록 전체 id를 배치 1회로(N+1 아님).
    final Map<String, _ReviewStats> stats = await _reviewStatsForMany(ids);

    return entries
        .map((MentorListItem e) => e.copyWith(
              profile: profiles[e.id],
              plans: plans[e.id] ?? const <MentorPlan>[],
              avgRating: stats[e.id]?.avg,
              reviewCount: stats[e.id]?.count ?? 0,
            ))
        .toList();
  }

  /// 전체 공개 멘토를 한 번에 로드한다 — 검색·과목 필터·정렬을 **전체 집합**에 적용하기
  /// 위함(최신 N명 창 검색 금지).
  ///
  /// RPC `mentor_directory_list_v2` 는 커서/서버 검색을 지원하지 않고 `p_limit` 만 받으며
  /// 서버 상한이 200 이다. 현재 공개 멘토 수는 이 상한 이내라 누락이 없다.
  /// SERVER_CURSOR_FOLLOWUP: 공개 멘토가 200 을 초과하면 서버 커서/검색 RPC 가 필요하다.
  Future<List<MentorListItem>> listComplete() => list(limit: directoryMaxLimit);

  /// 상세 화면 추가 정보(평균 답변시간 + 내 구독 여부). 프로필·요금제는 목록에서
  /// 받은 항목을 재사용하므로 여기서는 부족한 부분만 채운다.
  Future<MentorDetailExtras> fetchExtras(String mentorId) async {
    num? avgHours;
    try {
      final dynamic r = await _client.rpc(
        'get_mentor_avg_response_hours',
        params: <String, dynamic>{'p_mentor_id': mentorId},
      );
      if (r is num) avgHours = r;
    } catch (_) {
      avgHours = null; // 통계 없음 → '신규 멘토'
    }

    final _ReviewStats reviews = await _reviewStats(mentorId);

    bool subscribed = false;
    final String? uid = _client.auth.currentUser?.id;
    if (uid != null) {
      try {
        final Map<String, SubscriptionSummary> subs =
            await SubscriptionReader.fetchForStudent(_client, uid);
        subscribed = subs[mentorId]?.isActive ?? false;
      } catch (_) {
        subscribed = false;
      }
    }

    return MentorDetailExtras(
      avgResponseHours: avgHours,
      avgRating: reviews.avg,
      reviewCount: reviews.count,
      alreadySubscribed: subscribed,
    );
  }

  /// 한 멘토의 공개 리뷰 집계(상세 활동 통계용) — 배치 집계를 1건으로 재사용.
  Future<_ReviewStats> _reviewStats(String mentorId) async {
    final Map<String, _ReviewStats> m =
        await _reviewStatsForMany(<String>[mentorId]);
    return m[mentorId] ?? const _ReviewStats(0, null);
  }

  /// 여러 멘토의 '공개(visible) 리뷰' 평균 평점·개수(reviews 배치 집계).
  ///
  /// 공개 = moderation_state='visible' AND is_hidden=false AND is_blinded=false.
  /// ★ reviews 외 다른 조회는 하지 않는다(mentor_id·rating만 읽어 앱에서 그룹 집계).
  /// RLS/컬럼 부재 등 실패 시 빈 맵 → 평점·리뷰순은 동률(안정 정렬) 처리(날조 금지).
  Future<Map<String, _ReviewStats>> _reviewStatsForMany(
      List<String> mentorIds) async {
    if (mentorIds.isEmpty) return <String, _ReviewStats>{};
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('reviews')
          .select('mentor_id, rating')
          .inFilter('mentor_id', mentorIds)
          .eq('moderation_state', 'visible')
          .eq('is_hidden', false)
          .eq('is_blinded', false);
      final Map<String, int> count = <String, int>{};
      final Map<String, int> sum = <String, int>{};
      final Map<String, int> rated = <String, int>{};
      for (final Map<String, dynamic> r in rows) {
        final String? mid = r['mentor_id'] as String?;
        if (mid == null) continue;
        count[mid] = (count[mid] ?? 0) + 1;
        final Object? v = r['rating'];
        if (v is num) {
          sum[mid] = (sum[mid] ?? 0) + v.toInt();
          rated[mid] = (rated[mid] ?? 0) + 1;
        }
      }
      final Map<String, _ReviewStats> out = <String, _ReviewStats>{};
      count.forEach((String mid, int c) {
        final int n = rated[mid] ?? 0;
        out[mid] = _ReviewStats(c, n > 0 ? (sum[mid]! / n) : null);
      });
      return out;
    } catch (_) {
      return <String, _ReviewStats>{};
    }
  }

  Future<Map<String, MentorProfileInfo>> _profiles(List<String> ids) async {
    final Map<String, MentorProfileInfo> out = <String, MentorProfileInfo>{};
    final dynamic res = await _client.rpc(
      'mentor_profiles_for_directory_v2',
      params: <String, dynamic>{'p_ids': ids},
    );
    if (res is List) {
      for (final Object? row in res) {
        if (row is Map<String, dynamic>) {
          final MentorProfileInfo info = MentorProfileInfo.fromMap(row);
          out[info.userId] = info;
        }
      }
    }
    return out;
  }

  Future<Map<String, List<MentorPlan>>> _activePlans(List<String> ids) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('mentor_plans')
        .select('mentor_id, plan_tier, amount_cents, label')
        .inFilter('mentor_id', ids);

    final Map<String, List<MentorPlan>> out = <String, List<MentorPlan>>{};
    for (final Map<String, dynamic> r in rows) {
      final String? mentorId = r['mentor_id'] as String?;
      if (mentorId == null) continue;
      out
          .putIfAbsent(mentorId, () => <MentorPlan>[])
          .add(MentorPlan.fromMap(r));
    }
    return out;
  }
}

/// 리뷰 집계 결과(개수 + 평균 평점). 평균은 리뷰가 없으면 null.
class _ReviewStats {
  const _ReviewStats(this.count, this.avg);
  final int count;
  final double? avg;
}
