import 'package:flutter_test/flutter_test.dart';
import 'package:ssambership_app/features/mentors/data/mentor_directory_repository.dart';
import 'package:ssambership_app/features/mentors/data/mentor_models.dart';

/// 디렉터리 정본 전환(api_web_v1.mentor_directory_v1) — 페이지 순회(100행)
/// 무손실·무중복, 안전 상한 incomplete 플래그, full_name 미사용, 활성 요금제
/// 필터를 fake 게이트웨이로 고정한다(Supabase 미접촉).
class _FakeGateway extends MentorDirectoryGateway {
  _FakeGateway(this.rows, {this.plans = const <Map<String, dynamic>>[]});

  /// 뷰 정렬(created_at desc, mentor_id desc)이 이미 적용된 전체 행.
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> plans;

  int pageCalls = 0;
  final List<int> offsets = <int>[];
  List<String>? lastPlanIds;

  @override
  Future<List<Map<String, dynamic>>> selectDirectoryPage({
    required int offset,
    required int limit,
  }) async {
    pageCalls++;
    offsets.add(offset);
    if (offset >= rows.length) return <Map<String, dynamic>>[];
    final int end =
        (offset + limit) > rows.length ? rows.length : (offset + limit);
    return rows.sublist(offset, end);
  }

  @override
  Future<Map<String, dynamic>?> selectDirectoryRow(String mentorId) async {
    for (final Map<String, dynamic> r in rows) {
      if (r['mentor_id'] == mentorId) return r;
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> selectActivePlans(
      List<String> mentorIds) async {
    lastPlanIds = List<String>.of(mentorIds);
    return plans;
  }
}

/// 뷰 행 샘플 — 서버 계약 컬럼만 담는다(full_name 없음).
Map<String, dynamic> _viewRow(int i, {String? nickname}) => <String, dynamic>{
      'mentor_id': 'm-${i.toString().padLeft(4, '0')}',
      'nickname': nickname ?? '멘토$i',
      'university_name': '대학$i',
      'department_name': '학과$i',
      'teaching_subjects': <String>['math'],
      'intro_line': '소개$i',
      'school_verified': i.isEven,
      'avg_rating': i % 3 == 0 ? null : 4.0,
      'review_count': i % 3,
      'created_at': '2026-07-01T00:00:00Z',
    };

void main() {
  group('페이지 순회 — 무손실·무중복(200명 상한 제거)', () {
    for (final int total in <int>[201, 250]) {
      test('$total 명: 전원 로드 + 중복 0 + incomplete=false', () async {
        final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
          for (int i = total - 1; i >= 0; i--) _viewRow(i),
        ];
        final _FakeGateway g = _FakeGateway(rows);
        final MentorDirectoryResult r =
            await MentorDirectoryRepository(gateway: g).listComplete();

        expect(r.items.length, total, reason: '누락 0');
        expect(
          r.items.map((MentorListItem m) => m.id).toSet().length,
          total,
          reason: '중복 0',
        );
        expect(r.incomplete, isFalse);
        // 100행 페이지: 201명=3페이지(마지막 1행 short), 250명=3페이지(50행 short).
        expect(g.pageCalls, 3);
        expect(g.offsets, <int>[0, 100, 200]);
      });
    }

    test('정확히 100의 배수(200명) → 짧은 빈 페이지 1회로 종료(무한 루프 없음)',
        () async {
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
        for (int i = 0; i < 200; i++) _viewRow(i),
      ];
      final _FakeGateway g = _FakeGateway(rows);
      final MentorDirectoryResult r =
          await MentorDirectoryRepository(gateway: g).listComplete();
      expect(r.items.length, 200);
      expect(g.pageCalls, 3); // 100+100+0(빈 페이지 확인)
    });

    test('페이지 사이 중복 행(삽입 경합)이 와도 mentor_id dedupe 로 1개만', () async {
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
        for (int i = 0; i < 150; i++) _viewRow(i),
      ];
      // 두 번째 페이지 첫 행을 첫 페이지 마지막 행과 같은 멘토로 조작.
      rows[100] = Map<String, dynamic>.of(rows[99]);
      final _FakeGateway g = _FakeGateway(rows);
      final MentorDirectoryResult r =
          await MentorDirectoryRepository(gateway: g).listComplete();
      expect(r.items.length, 149);
      expect(r.items.map((MentorListItem m) => m.id).toSet().length, 149);
    });

    test('안전 상한(50페이지) 도달 → 침묵 절단 대신 incomplete=true', () async {
      // 항상 만석 페이지를 돌려주는 게이트웨이(5,000명 초과 상황).
      final _FakeGateway g = _FakeGateway(<Map<String, dynamic>>[
        for (int i = 0; i < MentorDirectoryRepository.pageSize * 60; i++)
          _viewRow(i),
      ]);
      final MentorDirectoryResult r =
          await MentorDirectoryRepository(gateway: g).listComplete();
      expect(r.incomplete, isTrue);
      expect(g.pageCalls, MentorDirectoryRepository.maxPages);
      expect(r.items.length,
          MentorDirectoryRepository.pageSize * MentorDirectoryRepository.maxPages);
    });
  });

  group('뷰 행 파싱 — full_name 미사용·표시명 폴백', () {
    test('nickname 트림 비면 "멘토" — full_name 키가 있어도 읽지 않는다', () async {
      final Map<String, dynamic> row = _viewRow(1, nickname: '  ');
      row['full_name'] = '유출되면 안 되는 실명';
      final MentorListItem item = MentorListItem.fromDirectoryViewMap(row);
      expect(item.displayName, '멘토');
      expect(item.searchHaystack.contains('유출되면'), isFalse);
    });

    test('게이트웨이 select 컬럼 목록에 full_name 이 없다(요청 자체 금지)', () {
      expect(
        MentorDirectoryGateway.directoryColumns.contains('full_name'),
        isFalse,
      );
      expect(
        MentorDirectoryGateway.directoryColumns.contains('mentor_id'),
        isTrue,
      );
    });

    test('avg_rating/review_count 는 뷰 값 그대로(날조 금지)', () {
      final MentorListItem rated =
          MentorListItem.fromDirectoryViewMap(_viewRow(1));
      expect(rated.avgRating, 4.0);
      expect(rated.reviewCount, 1);
      final MentorListItem unrated =
          MentorListItem.fromDirectoryViewMap(_viewRow(3));
      expect(unrated.avgRating, isNull);
      expect(unrated.reviewCount, 0);
    });
  });

  group('mentor_plans — is_active 서버 필터 + 행 파싱 이중 확인', () {
    test('is_active=false·누락 행은 붙지 않는다(누락을 true 로 날조 금지)', () async {
      final _FakeGateway g = _FakeGateway(
        <Map<String, dynamic>>[_viewRow(1)],
        plans: <Map<String, dynamic>>[
          <String, dynamic>{
            'mentor_id': 'm-0001',
            'plan_tier': 'standard',
            'amount_cents': 8490000,
            'label': null,
            'is_active': true,
          },
          <String, dynamic>{
            'mentor_id': 'm-0001',
            'plan_tier': 'premium',
            'amount_cents': 17490000,
            'label': null,
            'is_active': false, // 서버 필터를 통과했더라도 행 값으로 제외.
          },
          <String, dynamic>{
            'mentor_id': 'm-0001',
            'plan_tier': 'limited',
            'amount_cents': 2990000,
            'label': null,
            // is_active 누락 — true 로 날조하지 않는다.
          },
        ],
      );
      final MentorDirectoryResult r =
          await MentorDirectoryRepository(gateway: g).listComplete();
      final MentorListItem item = r.items.single;
      expect(item.plans.length, 1);
      expect(item.plans.single.planTier, 'standard');
      expect(g.lastPlanIds, <String>['m-0001']);
    });

    test('MentorPlan.fromMap — is_active 는 명시 true 만 true', () {
      expect(
        MentorPlan.fromMap(<String, dynamic>{
          'plan_tier': 'limited',
          'amount_cents': 2990000,
          'is_active': true,
        }).isActive,
        isTrue,
      );
      expect(
        MentorPlan.fromMap(<String, dynamic>{
          'plan_tier': 'limited',
          'amount_cents': 2990000,
        }).isActive,
        isFalse,
      );
    });
  });
}
