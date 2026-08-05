import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/entitlement/subscription_summary.dart';
import '../../../core/entitlement/weekly_question_usage.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../../shared/errors/app_error.dart';
import '../../question_room/data/mentor_lookup_repository.dart';
import '../../question_room/data/models/question_thread.dart';
import '../../question_room/data/models/room.dart';
import '../../question_room/data/question_room_read_repository.dart';
import '../../question_room/data/student_lookup_repository.dart';
import '../../question_room/data/thread_status_counts.dart';
import 'mypage_models.dart';

/// 마이페이지 읽기 전용 레포지토리. ★ 어떤 mutate 도 하지 않는다(조회만).
/// RLS(본인 행만)에 의존하고, 구독·멘토 조회는 기존 S2/S4 레이어를 재사용한다.
class MyPageRepository {
  const MyPageRepository();

  final QuestionRoomReadRepository _rooms = const QuestionRoomReadRepository();
  final MentorLookupRepository _mentors = const MentorLookupRepository();
  final StudentLookupRepository _students = const StudentLookupRepository();

  SupabaseClient get _client {
    final SupabaseClient? c = SupabaseInit.clientOrNull;
    if (c == null) {
      throw const AppError('백엔드에 연결되어 있지 않아요.');
    }
    return c;
  }

  String get _uid {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) throw const AppError('로그인이 필요해요.');
    return id;
  }

  /// 화면 진입 시 1회 호출. 역할에 맞는 데이터를 모아 반환한다.
  /// N17: 서로 독립인 조회는 병렬로 묶는다 — 종전 완전 직렬 팬아웃 제거.
  Future<MyPageData> load() async {
    final AuthService auth = AuthService.instance;

    if (auth.currentRole == AppRole.mentor) {
      final List<dynamic> r = await Future.wait(<Future<dynamic>>[
        _loadProfile(auth),
        _loadMentorDashboard(),
      ]);
      return MyPageData(
        role: AppRole.mentor,
        profile: r[0] as MyProfile,
        mentor: r[1] as MentorDashboard,
      );
    }

    final List<dynamic> r = await Future.wait(<Future<dynamic>>[
      _loadProfile(auth),
      _loadSubscriptions(),
      _loadCash(),
    ]);
    return MyPageData(
      role: auth.currentRole,
      profile: r[0] as MyProfile,
      subscriptions: r[1] as List<SubscriptionCardInfo>,
      cash: r[2] as CashSummary,
    );
  }

  Future<MyProfile> _loadProfile(AuthService auth) async {
    String? email;
    String? grade;
    try {
      final Map<String, dynamic>? row = await _client
          .from('users')
          .select('email, grade_level')
          .eq('id', _uid)
          .maybeSingle();
      email = (row?['email'] as String?)?.trim();
      grade = (row?['grade_level'] as String?)?.trim();
    } catch (_) {
      // 프로필 보강 read 실패는 치명적이지 않다 — 이름/역할만으로도 화면은 뜬다.
    }
    return MyProfile(
      name: auth.displayName,
      roleLabel: auth.roleLabel,
      email: (email?.isEmpty ?? true) ? null : email,
      grade: (grade?.isEmpty ?? true) ? null : grade,
    );
  }

  /// 학생: 멘토별 구독 카드. 잔여수는 미확정 → null(상태로 표기).
  Future<List<SubscriptionCardInfo>> _loadSubscriptions() async {
    final Map<String, SubscriptionSummary> subs =
        await SubscriptionReader.fetchForStudent(_client, _uid);
    if (subs.isEmpty) return const <SubscriptionCardInfo>[];
    // A2: 멘토별 주간 질문 사용량(RPC). ★ 한도값 재하드코딩 없이 RPC 반환만 사용.
    //     실패하면 null → 카드가 기존 상태 문구로 조용히 폴백(흐름 안 막음).
    // N17: 멘토 표시명과 사용량 RPC 는 서로 독립 — 병렬 조회.
    final Map<String, WeeklyQuestionUsage?> usageByMentor =
        <String, WeeklyQuestionUsage?>{};
    final List<dynamic> nu = await Future.wait(<Future<dynamic>>[
      _mentors.fetchMany(subs.keys),
      Future.wait(subs.keys.map((String mentorId) async {
        usageByMentor[mentorId] =
            await _rooms.weeklyUsage(studentId: _uid, mentorId: mentorId);
      })),
    ]);
    final Map<String, MentorPublic> names = nu[0] as Map<String, MentorPublic>;
    final List<SubscriptionCardInfo> cards = <SubscriptionCardInfo>[
      for (final SubscriptionSummary s in subs.values)
        SubscriptionCardInfo(
          mentorName: names[s.mentorId]?.displayName ?? '멘토',
          isActive: s.isActive,
          status: s.status,
          planTier: s.planTier,
          nextRenewal: s.nextRenewal,
          remaining: s.remaining, // 미확정이면 null
          usage: usageByMentor[s.mentorId],
        ),
    ];
    // 활성 구독 먼저, 그다음 멘토명 순.
    cards.sort((SubscriptionCardInfo a, SubscriptionCardInfo b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.mentorName.compareTo(b.mentorName);
    });
    return cards;
  }

  /// 학생: 캐시 잔액 + 최근 내역(조회만). 지갑이 없으면 balance null.
  /// N17: 잔액과 내역은 서로 독립 — 병렬 조회.
  Future<CashSummary> _loadCash() async {
    final List<dynamic> r = await Future.wait(<Future<dynamic>>[
      _loadCashBalance(),
      _loadCashRecent(),
    ]);
    return CashSummary(
        balanceCents: r[0] as int?, recent: r[1] as List<CashEntry>);
  }

  Future<int?> _loadCashBalance() async {
    int? balance;
    try {
      final Map<String, dynamic>? wallet = await _client
          .from('cash_wallets')
          .select('balance_cents')
          .eq('user_id', _uid)
          .maybeSingle();
      final Object? v = wallet?['balance_cents'];
      if (v is int) balance = v;
      if (v is num) balance = v.toInt();
    } catch (_) {
      // 지갑 read 실패 → 잔액 미확인(비움). 날조하지 않는다.
    }
    return balance;
  }

  Future<List<CashEntry>> _loadCashRecent() async {
    final List<CashEntry> recent = <CashEntry>[];
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('cash_ledger')
          .select('delta_cents, created_at, reason')
          .eq('user_id', _uid)
          .order('created_at', ascending: false)
          .limit(5);
      for (final Map<String, dynamic> r in rows) {
        final Object? d = r['delta_cents'];
        final int delta = d is int ? d : (d is num ? d.toInt() : 0);
        final Object? reasonRaw = r['reason'];
        recent.add(CashEntry(
          deltaCents: delta,
          createdAt: DateTime.tryParse('${r['created_at']}')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
          reason: reasonRaw is String ? reasonRaw : null,
        ));
      }
    } catch (_) {
      // 내역 read 실패 → 빈 목록.
    }
    return recent;
  }

  /// 멘토: 답변·정산 요약(조회만). 출금은 웹.
  /// N17: 정산 조회는 방→스레드 체인과 독립 — 병렬 실행.
  Future<MentorDashboard> _loadMentorDashboard() async {
    final Future<int?> settlementF = _loadLatestSettlement();
    final List<Room> rooms = await _rooms.myRooms();
    final List<String> roomIds = rooms.map((Room r) => r.id).toList();
    final List<QuestionThread> threads = await _rooms.threadsForRooms(roomIds);
    final ThreadStatusCounts counts = ThreadStatusCounts.from(threads);
    final int? settlement = await settlementF;

    return MentorDashboard(
      studentCount: rooms.length,
      pendingAnswers: counts.pending,
      latestSettlementCents: settlement,
    );
  }

  Future<int?> _loadLatestSettlement() async {
    // 학생 이름 조회는 대시보드 수치엔 불필요하지만, 연결 학생 수는 방 수로 센다.
    int? settlement;
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('subscription_settlement_items')
          .select('mentor_amount_cents, created_at')
          .eq('mentor_id', _uid)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        final Object? v = rows.first['mentor_amount_cents'];
        if (v is int) settlement = v;
        if (v is num) settlement = v.toInt();
      }
    } catch (_) {
      // 정산 read 실패 → 표시 생략(null).
    }
    return settlement;
  }

  /// 멘토: 구독 학생 이름 목록(선택 표시용, 조회만). 화면에서 필요 시 사용.
  Future<List<String>> mentorStudentNames() async {
    final List<Room> rooms = await _rooms.myRooms();
    if (rooms.isEmpty) return const <String>[];
    final Map<String, StudentPublic> names =
        await _students.fetchMany(rooms.map((Room r) => r.studentId));
    return <String>[
      for (final Room r in rooms) names[r.studentId]?.displayName ?? '학생',
    ];
  }
}
