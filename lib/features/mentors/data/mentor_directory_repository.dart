import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/entitlement/subscription_summary.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import 'mentor_models.dart';

/// 디렉터리 뷰 접근 통로(테스트 seam) — 계약 수렴 후 정본 소스는
/// `api_web_v1.mentor_directory_v1` 뷰다(anon+authenticated SELECT).
///
/// ★ 구 RPC(mentor_directory_list_v2 / mentor_profiles_for_directory_v2 /
///   mentor_user_public_v2)는 앱 권한이 REVOKE 됐다 — 호출 코드 자체를 남기지
///   않는다. 행 존재 자체가 '활성·승인 멘토'라는 서버 보장이다.
class MentorDirectoryGateway {
  const MentorDirectoryGateway();

  /// 뷰에서 읽는 컬럼(명시 select — full_name 은 뷰에 없고, 읽지도 않는다).
  static const String directoryColumns =
      'mentor_id, nickname, university_name, department_name, '
      'teaching_subjects, intro_line, school_verified, '
      'avg_rating, review_count, created_at';

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  /// 디렉터리 1페이지 — created_at desc + mentor_id desc(동시각 타이브레이크),
  /// [offset]부터 [limit]행. 페이지 사이 새 행이 끼어도 정렬 키가 안정적이라
  /// 중복은 상위(레포)의 mentor_id dedupe 로 걸러진다.
  Future<List<Map<String, dynamic>>> selectDirectoryPage({
    required int offset,
    required int limit,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .schema('api_web_v1')
        .from('mentor_directory_v1')
        .select(directoryColumns)
        .order('created_at', ascending: false)
        .order('mentor_id', ascending: false)
        .range(offset, offset + limit - 1);
    return rows;
  }

  /// 멘토 1명 뷰 행(질문방 상대 표시·상세 딥링크용). 없으면 null —
  /// 비공개(비활성·미승인) 멘토는 중립 표시로 처리하고 오류로 만들지 않는다.
  Future<Map<String, dynamic>?> selectDirectoryRow(String mentorId) {
    return _client
        .schema('api_web_v1')
        .from('mentor_directory_v1')
        .select(directoryColumns)
        .eq('mentor_id', mentorId)
        .maybeSingle();
  }

  /// 여러 멘토의 **활성** 요금제(is_active=true 서버 필터 + 행 값 파싱).
  Future<List<Map<String, dynamic>>> selectActivePlans(
      List<String> mentorIds) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('mentor_plans')
        .select('mentor_id, plan_tier, amount_cents, label, is_active')
        .inFilter('mentor_id', mentorIds)
        .eq('is_active', true);
    return rows;
  }
}

/// 전체 디렉터리 로드 결과 — 안전 상한에 걸리면 [incomplete] 로 드러낸다
/// (조용한 절단 금지: 화면이 '일부만 표시 중'을 안내할 수 있어야 한다).
class MentorDirectoryResult {
  const MentorDirectoryResult({
    required this.items,
    required this.incomplete,
  });

  final List<MentorListItem> items;

  /// true = 페이지 안전 상한(50페이지)에 걸려 뒤가 더 있을 수 있음.
  final bool incomplete;
}

/// 멘토 찾기(공개·열람 전용) 레포지토리.
///
/// 소스(모두 공개 조회 가능):
/// - 목록/프로필/평점: 뷰 `api_web_v1.mentor_directory_v1`
///   (100행 페이지를 짧은 페이지가 나올 때까지 순회 — 서버 상한 200 제약 제거)
/// - `mentor_plans` (is_active=true) : 요금제(가격 '표시'만)
/// - `get_mentor_avg_response_hours(p_mentor_id)` : 평균 답변시간(없으면 null)
/// 구독 여부는 본인 행만 보이는 subscriptions 를 [SubscriptionReader] 로 읽는다.
class MentorDirectoryRepository {
  const MentorDirectoryRepository(
      {MentorDirectoryGateway gateway = const MentorDirectoryGateway()})
      : _gateway = gateway;

  final MentorDirectoryGateway _gateway;

  /// 페이지 크기(뷰 range 1회분).
  static const int pageSize = 100;

  /// 페이지 순회 안전 상한 — 5,000명(100×50)을 넘으면 [MentorDirectoryResult]
  /// 의 incomplete 로 알린다(무한 루프 방지 + 조용한 절단 금지).
  static const int maxPages = 50;

  /// 전체 공개 멘토 로드 — 검색·과목 필터·정렬을 **전체 집합**에 적용하기 위함.
  ///
  /// ★ C28 스케일 경계(의도된 트레이드오프): 검색은 한글 라벨 정규화
  ///   (subjectViews·searchHaystack)가 앱에 있어 전량 로드 후 로컬 처리가
  ///   정확성 면에서 정본이다. 멘토 수백 명 규모까지는 이 방식이 단순·정확
  ///   하며, [maxPages] 상한 도달(incomplete=true)이 서버측 검색 RPC(정규화
  ///   로직 서버 이관 포함)로 이행할 신호다 — 조용한 절단은 없다.
  ///
  /// created_at desc + mentor_id desc 로 [pageSize]씩 읽어 짧은 페이지가 나올
  /// 때까지 순회하고, 페이지 사이 삽입으로 생길 수 있는 중복은 mentor_id 로
  /// 제거한다(누락 0·중복 0). 결과 항목엔 활성 요금제를 붙인다.
  Future<MentorDirectoryResult> listComplete() async {
    final List<MentorListItem> entries = <MentorListItem>[];
    final Set<String> seenIds = <String>{};
    bool incomplete = false;

    int offset = 0;
    for (int page = 0;; page++) {
      if (page >= maxPages) {
        incomplete = true; // 상한 도달 — 침묵 절단 대신 명시 플래그.
        break;
      }
      final List<Map<String, dynamic>> rows =
          await _gateway.selectDirectoryPage(offset: offset, limit: pageSize);
      for (final Map<String, dynamic> row in rows) {
        final MentorListItem item = MentorListItem.fromDirectoryViewMap(row);
        if (seenIds.add(item.id)) entries.add(item);
      }
      if (rows.length < pageSize) break; // 짧은 페이지 = 마지막.
      offset += rows.length;
    }

    if (entries.isEmpty) {
      return MentorDirectoryResult(
          items: const <MentorListItem>[], incomplete: incomplete);
    }

    final List<String> ids =
        entries.map((MentorListItem e) => e.id).toList(growable: false);
    final Map<String, List<MentorPlan>> plans = await _activePlans(ids);

    return MentorDirectoryResult(
      items: entries
          .map((MentorListItem e) =>
              e.copyWith(plans: plans[e.id] ?? const <MentorPlan>[]))
          .toList(),
      incomplete: incomplete,
    );
  }

  /// 멘토 1명 목록 항목(알림 딥링크 → 상세 진입용). 뷰에 없으면 null
  /// (비공개 멘토 — 호출부가 중립 폴백).
  Future<MentorListItem?> fetchListItemById(String mentorId) async {
    final Map<String, dynamic>? row =
        await _gateway.selectDirectoryRow(mentorId);
    if (row == null) return null;
    final MentorListItem item = MentorListItem.fromDirectoryViewMap(row);
    final Map<String, List<MentorPlan>> plans =
        await _activePlans(<String>[item.id]);
    return item.copyWith(plans: plans[item.id] ?? const <MentorPlan>[]);
  }

  /// 상세 화면 추가 정보(평균 답변시간 + 내 구독 여부). 프로필·요금제·평점은
  /// 목록(뷰 행)에서 받은 항목을 재사용하므로 여기서는 부족한 부분만 채운다.
  ///
  /// C26: [knownAvgRating]/[knownReviewCount] 로 목록 항목의 평점·리뷰 수를
  /// 넘기면 같은 뷰 단건 재조회를 생략한다(상세 진입·resume 마다의 중복 제거).
  /// 안 넘긴 호출(구 계약)만 뷰 행을 조회한다. 서로 독립인 조회는 병렬.
  Future<MentorDetailExtras> fetchExtras(
    String mentorId, {
    double? knownAvgRating,
    int? knownReviewCount,
  }) async {
    final Future<num?> avgHoursF = _fetchAvgResponseHours(mentorId);
    final Future<bool> subscribedF = _fetchMySubscribed(mentorId);

    double? avgRating = knownAvgRating;
    int reviewCount = knownReviewCount ?? 0;
    if (knownReviewCount == null) {
      // 평점·리뷰 수 — 뷰 행이 정본(별도 reviews 집계 쿼리 제거).
      try {
        final Map<String, dynamic>? row =
            await _gateway.selectDirectoryRow(mentorId);
        if (row != null) {
          avgRating = (row['avg_rating'] as num?)?.toDouble();
          reviewCount = (row['review_count'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {
        // 조회 실패 → 평점 미표시(날조 금지).
      }
    }

    return MentorDetailExtras(
      avgResponseHours: await avgHoursF,
      avgRating: avgRating,
      reviewCount: reviewCount,
      alreadySubscribed: await subscribedF,
    );
  }

  Future<num?> _fetchAvgResponseHours(String mentorId) async {
    try {
      final dynamic r = await _client.rpc(
        'get_mentor_avg_response_hours',
        params: <String, dynamic>{'p_mentor_id': mentorId},
      );
      if (r is num) return r;
    } catch (_) {
      // 통계 없음 → '신규 멘토'
    }
    return null;
  }

  Future<bool> _fetchMySubscribed(String mentorId) async {
    // ★ 병렬 조회 헬퍼는 절대 throw 하지 않는다 — 클라이언트 미연결 포함
    //   모든 실패를 안에서 흡수해야 대기 전 실패가 unhandled 로 새지 않는다.
    try {
      final SupabaseClient client = _client;
      final String? uid = client.auth.currentUser?.id;
      if (uid == null) return false;
      final Map<String, SubscriptionSummary> subs =
          await SubscriptionReader.fetchForStudent(client, uid);
      return subs[mentorId]?.isActive ?? false;
    } catch (_) {
      return false;
    }
  }

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  Future<Map<String, List<MentorPlan>>> _activePlans(List<String> ids) async {
    final List<Map<String, dynamic>> rows =
        await _gateway.selectActivePlans(ids);
    final Map<String, List<MentorPlan>> out = <String, List<MentorPlan>>{};
    for (final Map<String, dynamic> r in rows) {
      final String? mentorId = r['mentor_id'] as String?;
      if (mentorId == null) continue;
      final MentorPlan plan = MentorPlan.fromMap(r);
      // 서버 필터(is_active=true)와 행 파싱의 이중 확인 — 비활성 행 미노출.
      if (!plan.isActive) continue;
      out.putIfAbsent(mentorId, () => <MentorPlan>[]).add(plan);
    }
    return out;
  }
}
