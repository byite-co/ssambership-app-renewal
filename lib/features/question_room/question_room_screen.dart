import 'package:flutter/material.dart';

import '../../app/app_tabs.dart';
import '../../core/auth/auth_service.dart';
import '../../core/commerce/commerce_policy.dart';
import '../../core/entitlement/subscription_status_display.dart';
import '../../core/refresh/data_refresh_bus.dart';
import '../../core/entitlement/subscription_summary.dart';
import '../../core/entitlement/weekly_question_usage.dart';
import '../../core/supabase/supabase_client.dart';
import '../../design/shape_tokens.dart';
import '../../design/spacing_tokens.dart';
import '../../design/tokens/color_tokens.dart';
import '../../design/typography_tokens.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/initial_avatar.dart';
import '../../design/widgets/quota_bar.dart';
import '../../design/widgets/status_pill.dart';
import '../../shared/format/formatters.dart';
import '../../shared/widgets/commerce_notice_card.dart';
import 'data/mentor_lookup_repository.dart';
import 'data/models/room.dart';
import 'data/question_room_read_repository.dart';
import 'ui/mentor/mentor_inbox_screen.dart';
import 'ui/mentor_room_home_screen.dart';
import '../../shared/errors/friendly_error.dart';

/// 질문방 탭(1뎁스). HomeShell 이 AppBar/하단탭을 제공하므로 본문만 구성(자체 Scaffold 없음).
///
/// ★ role 분기:
///   - student → 내 멘토방 목록(S4).
///   - mentor  → 받은 학생 목록(S5, [MentorInboxScreen]).
///   - admin/guest → 차단(이 앱은 학생·멘토 전용).
class QuestionRoomScreen extends StatelessWidget {
  const QuestionRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    switch (AuthService.instance.currentRole) {
      case AppRole.mentor:
        return const MentorInboxScreen();
      case AppRole.student:
        return const _StudentRoomList();
      case AppRole.admin:
      case AppRole.guest:
        return const EmptyState(
          icon: Icons.forum_rounded,
          title: '질문방은 학생·멘토 전용이에요',
          message: '학생 또는 멘토 계정으로 이용해 주세요.',
        );
    }
  }
}

/// 학생용 1뎁스 = 내 멘토방 목록(카카오톡식). (S4)
class _StudentRoomList extends StatefulWidget {
  const _StudentRoomList();

  @override
  State<_StudentRoomList> createState() => _StudentRoomListState();
}

/// 목록 한 행에 필요한 묶음(방 + 멘토 표시명 + 구독 요약 + 주간 사용량).
class _RoomItem {
  const _RoomItem(
      {required this.room,
      this.mentor,
      this.sub,
      this.usage,
      required this.lastActivity});
  final Room room;
  final MentorPublic? mentor;
  final SubscriptionSummary? sub;

  /// A2: 이 멘토와의 이번 주 질문 사용량(RPC). null = 미조회/실패 → 표시 생략.
  final WeeklyQuestionUsage? usage;

  /// N37: 실제 마지막 활동 = max(방 updated_at, 스레드 updated_at) — 서버는
  /// Q&A 활동 시 방 행을 갱신하지 않으므로(트리거·RPC 실측) 방 값만으로는
  /// 동결된다. 멘토 인박스와 동일 기준으로 통일.
  final DateTime lastActivity;

  String get mentorName => mentor?.displayName ?? '멘토';
}

class _StudentRoomListState extends State<_StudentRoomList>
    with WidgetsBindingObserver {
  final QuestionRoomReadRepository _repo = const QuestionRoomReadRepository();
  final MentorLookupRepository _mentors = const MentorLookupRepository();

  late Future<List<_RoomItem>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
    // §4: 웹에서 구독·결제 후 앱 복귀 시 방 목록·구독 상태 재조회
    // (IndexedStack 탭이라 재빌드가 없으므로 lifecycle 신호로 갱신).
    WidgetsBinding.instance.addObserver(this);
    // N35: 탭 전환·재선택, 무료 질문 생성 등 질문방 표면 신호 수신.
    DataRefreshBus.questionRoomsGeneration.addListener(_refresh);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    DataRefreshBus.questionRoomsGeneration.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<List<_RoomItem>> _load() async {
    final List<Room> rooms = await _repo.myRooms();
    if (rooms.isEmpty) return <_RoomItem>[];
    final String? studentId = SupabaseInit.clientOrNull?.auth.currentUser?.id;
    final Map<String, SubscriptionSummary> subs = studentId == null
        ? <String, SubscriptionSummary>{}
        : await SubscriptionReader.fetchForStudent(
            SupabaseInit.clientOrNull!, studentId);
    final Map<String, MentorPublic> names =
        await _mentors.fetchMany(rooms.map((Room r) => r.mentorId));
    // A2: 멘토별 주간 사용량(RPC). ★ 한도값 재하드코딩 없이 RPC 반환만. 실패는 null(표시 생략).
    final Map<String, WeeklyQuestionUsage?> usageByMentor =
        <String, WeeklyQuestionUsage?>{};
    if (studentId != null) {
      final Set<String> mentorIds = rooms.map((Room r) => r.mentorId).toSet();
      await Future.wait(mentorIds.map((String mentorId) async {
        usageByMentor[mentorId] =
            await _repo.weeklyUsage(studentId: studentId, mentorId: mentorId);
      }));
    }
    // N37: 방별 실제 활동시각 — 스레드 슬림 조회 1회(방·상태·활동시각만).
    final Map<String, DateTime> lastByRoom = <String, DateTime>{};
    try {
      final List<ThreadStatusRow> statusRows = await _repo
          .threadStatusRowsForRooms(rooms.map((Room r) => r.id).toList());
      for (final ThreadStatusRow t in statusRows) {
        final DateTime? cur = lastByRoom[t.roomId];
        if (cur == null || t.updatedAt.isAfter(cur)) {
          lastByRoom[t.roomId] = t.updatedAt;
        }
      }
    } catch (_) {
      // 실패 시 방 updated_at 폴백(표시 저하일 뿐 흐름은 막지 않는다).
    }
    DateTime activityOf(Room r) {
      final DateTime? t = lastByRoom[r.id];
      return (t != null && t.isAfter(r.updatedAt)) ? t : r.updatedAt;
    }
    final List<_RoomItem> items = rooms
        .map((Room r) => _RoomItem(
              lastActivity: activityOf(r),
              room: r,
              mentor: names[r.mentorId],
              sub: subs[r.mentorId],
              usage: usageByMentor[r.mentorId],
            ))
        .toList();
    // N37: 표시·정렬 기준 통일 — 실제 활동시각 내림차순(인박스와 동일).
    items.sort(
        (_RoomItem a, _RoomItem b) => b.lastActivity.compareTo(a.lastActivity));
    return items;
  }

  void _refresh() {
    if (!mounted) return; // §4: dispose 후 setState 금지.
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            12,
            AppSpacing.screenH,
            8,
          ),
          child: TextField(
            style: AppType.body,
            onChanged: (String v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: '멘토 검색',
              prefixIcon:
                  const Icon(Icons.search_rounded, color: ColorTokens.muted),
              filled: true,
              fillColor: ColorTokens.elevated,
              border: OutlineInputBorder(
                borderRadius: AppShape.inputRadius,
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        Expanded(child: _list()),
        // 커머스 제로: 하단 '멘토 구독하기'(구매 유도) 바 제거. 구독 없음은
        // 빈 상태의 안내 카드로만 표시한다(버튼 없음).
      ],
    );
  }

  Widget _list() {
    return FutureBuilder<List<_RoomItem>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<_RoomItem>> snap) {
        // R1(20건 리뷰): future 교체형 새로고침(N35 탭 신호·resume) 동안
        // 이전 데이터가 스냅샷에 유지되므로, 데이터가 있으면 스피너 대신
        // 기존 목록을 계속 보여준다(탭 전환마다 번쩍임 제거).
        if (snap.connectionState != ConnectionState.done && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorView(
              message: '목록을 불러오지 못했어요.\n${friendlyError(snap.error!)}');
        }
        final List<_RoomItem> all = snap.data ?? <_RoomItem>[];
        if (all.isEmpty) {
          return Column(
            children: <Widget>[
              Expanded(
                child: EmptyState(
                  icon: Icons.forum_rounded,
                  title: '아직 질문방이 없어요',
                  message: '멘토를 구독하면 1:1 질문방이 열려요',
                  // CTA는 기존 탭 전환 경로만 재사용(멘토 찾기 탭). 결제 유도 아님.
                  actionLabel: '멘토 찾기',
                  onAction: () => TabNavigator.go(AppTab.mentors),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  0,
                  AppSpacing.screenH,
                  16,
                ),
                child: CommerceNoticeCard(text: kSubscribeNoticeText),
              ),
            ],
          );
        }
        final List<_RoomItem> items = _query.isEmpty
            ? all
            : all
                .where((_RoomItem it) => it.mentorName.contains(_query))
                .toList();
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off,
            title: '검색 결과가 없어요',
            message: '다른 이름으로 검색해 보세요.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            8,
            AppSpacing.screenH,
            16,
          ),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (BuildContext context, int i) =>
              _RoomTile(item: items[i], onOpen: () => _open(items[i])),
        );
      },
    );
  }

  Future<void> _open(_RoomItem it) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MentorRoomHomeScreen(
          room: it.room,
          mentorName: it.mentorName,
          sub: it.sub,
        ),
      ),
    );
    if (mounted) _refresh(); // 돌아오면 최신화(새 질문/확인 반영).
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.item, required this.onOpen});
  final _RoomItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final SubscriptionSummary? sub = item.sub;
    // 구독 상태칩·갱신일은 넘칠 수 있어 Wrap 으로 자연스럽게 줄바꿈(정보 유지, 배치만 정돈).
    final WeeklyQuestionUsage? usage = item.usage;
    final bool hasQuotaBar = usage != null && usage.hasQuota;
    final SubscriptionStatusDisplay? statusDisp = sub == null
        ? null
        : subscriptionStatusDisplay(sub.status, isActive: sub.isActive);
    // 상태칩 + 잔여를 한 줄로(정보 순서 유지). 넘치면 Wrap 이 자연 줄바꿈.
    final List<Widget> meta = <Widget>[
      // D1-B: 상태 도트 + 기존 상태칩.
      if (statusDisp != null)
        StatusPill(
          label: statusDisp.label,
          tone: statusDisp.tone,
          showDot: true,
        ),
      // A2: 잔여 바로 못 보여줄 때(한도 정보 없음)만 텍스트 폴백.
      if (!hasQuotaBar && usage?.planQuotaLabel != null)
        Text(usage!.planQuotaLabel!, style: AppType.caption),
      if (sub?.nextRenewal != null)
        Text(
          '다음 갱신 ${Formatters.shortDate(sub!.nextRenewal!)}',
          style: AppType.caption,
        ),
    ];
    return AppCard(
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // 아바타: 역할색 옅은 틴트 배경 + 이니셜(이 카드의 시그니처 요소).
          InitialAvatar(name: item.mentorName, size: 48),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 이름(title) + 우측 상단 활동시각(caption): 한 줄 정렬.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.mentorName,
                        style: AppType.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    // 마지막 활동시각 — N37: 방·스레드 max(인박스와 동일 기준).
                    Text(
                      '${Formatters.relativeKorean(item.lastActivity)} 활동',
                      style: AppType.caption,
                    ),
                  ],
                ),
                if (meta.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.s8),
                  Wrap(
                    spacing: AppSpacing.s8,
                    runSpacing: AppSpacing.s4 + 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: meta,
                  ),
                ],
                // D1-A: 주간 잔여 질문권 프로그레스 바(있는 값만 — RPC used/limit).
                if (hasQuotaBar) ...<Widget>[
                  const SizedBox(height: AppSpacing.s8),
                  QuotaBar(used: usage.used, limit: usage.limit),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: ColorTokens.danger),
        ),
      ),
    );
  }
}
