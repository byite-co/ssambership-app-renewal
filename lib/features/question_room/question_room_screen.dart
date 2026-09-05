import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';
import '../../app/app_route_paths.dart';
import '../../app/app_scope.dart';
import '../../app/app_tabs.dart';
import '../../core/auth/auth_service.dart' show AppRole;
import '../../core/commerce/commerce_policy.dart';
import '../../core/entitlement/subscription_status_display.dart';
import '../../core/refresh/data_refresh_bus.dart';
import '../../core/entitlement/subscription_summary.dart';
import '../../core/entitlement/weekly_question_usage.dart';
import '../../design/role_theme.dart' show RoleTheme;
import '../../design/tokens/app_spacing.dart';
import '../../design/tokens/app_typography.dart';
import '../../design/widgets/app_empty_state.dart';
import '../../design/widgets/app_input_field.dart';
import '../../design/widgets/app_page.dart';
import '../../design/widgets/glass_card.dart';
import '../../design/widgets/initial_avatar.dart';
import '../../design/widgets/status_pill.dart';
import '../../shared/format/formatters.dart';
import '../../shared/labels/subscription_copy.dart';
import '../../shared/widgets/commerce_notice_card.dart';
import '../mentors/format/mentor_price_format.dart';
import 'data/mentor_lookup_repository.dart';
import 'data/mentor_note_format.dart';
import 'data/models/connection_note.dart';
import 'data/models/question_thread.dart';
import 'data/models/room.dart';
import 'data/question_room_read_repository.dart';
import 'ui/mentor/mentor_inbox_screen.dart';
import 'ui/mentor_room_home_screen.dart';
import 'ui/widgets/note_preview_line.dart';
import '../../shared/errors/friendly_error.dart';
import '../../shared/widgets/screen_visibility.dart';

/// 질문방 탭(1뎁스). HomeShell 이 AppBar/하단탭을 제공하므로 본문만 구성(자체 Scaffold 없음).
///
/// ★ role 분기(역할은 AppScope 의 auth 에서 읽는다 — A-2):
///   - student → 내 멘토방 목록(S4).
///   - mentor  → 받은 학생 목록(S5, [MentorInboxScreen]).
///   - admin/guest → 차단(이 앱은 학생·멘토 전용).
class QuestionRoomScreen extends StatelessWidget {
  const QuestionRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    switch (AppScope.of(context).auth.currentRole) {
      case AppRole.mentor:
        return const MentorInboxScreen();
      case AppRole.student:
        return const _StudentRoomList();
      case AppRole.admin:
      case AppRole.guest:
        return const AppEmptyState(
          icon: Icons.forum_rounded,
          title: '질문방은 학생·멘토 전용이에요',
          description: '학생 또는 멘토 계정으로 이용해 주세요.',
        );
    }
  }
}

/// 학생용 1뎁스 = 내 멘토방 목록(design-v3 §3-1). (S4)
class _StudentRoomList extends StatefulWidget {
  const _StudentRoomList();

  @override
  State<_StudentRoomList> createState() => _StudentRoomListState();
}

/// 목록 한 행에 필요한 묶음(방 + 멘토 표시명 + 구독 요약 + 주간 사용량 + 최근 노트).
class _RoomItem {
  const _RoomItem({
    required this.room,
    this.mentor,
    this.sub,
    this.usage,
    required this.lastActivity,
    this.answeredCount = 0,
    this.latestNote,
  });
  final Room room;
  final MentorPublic? mentor;
  final SubscriptionSummary? sub;

  /// A2: 이 멘토와의 이번 주 질문 사용량(RPC). null = 미조회/실패 → 표시 생략.
  final WeeklyQuestionUsage? usage;

  /// N37: 실제 마지막 활동 = max(방 updated_at, 스레드 updated_at) — 서버는
  /// Q&A 활동 시 방 행을 갱신하지 않으므로(트리거·RPC 실측) 방 값만으로는
  /// 동결된다. 멘토 인박스와 동일 기준으로 통일.
  final DateTime lastActivity;

  /// 답변이 와서 확인을 기다리는 질문 수(스레드 상태 answered) — '답변 N' 배지.
  final int answeredCount;

  /// 멘토가 남긴 최근 노트(§3-1 "노트가 목록에서 먼저 보입니다"). 없으면 null.
  final ConnectionNote? latestNote;

  String get mentorName => mentor?.displayName ?? '멘토';
}

class _StudentRoomListState extends State<_StudentRoomList>
    with WidgetsBindingObserver, ResumeVisibilityGate {
  // A-2: 레포지토리·구독 리더·사용자 id 는 AppScope 에서 받는다(직접 생성 0).
  late final AppDependencies _deps;
  QuestionRoomReadRepository get _repo => _deps.questionRoomRead;
  MentorLookupRepository get _mentors => _deps.mentorLookup;

  late Future<List<_RoomItem>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _deps = AppScope.of(context);
    _future = _load();
    // §4: 웹에서 구독·결제 후 앱 복귀 시 방 목록·구독 상태 재조회
    // (IndexedStack 탭이라 재빌드가 없으므로 lifecycle 신호로 갱신).
    WidgetsBinding.instance.addObserver(this);
    // N35: 탭 전환·재선택, 무료 질문 생성 등 질문방 표면 신호 수신.
    DataRefreshBus.questionRoomsGeneration.addListener(_refresh);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) handleResumed();
  }

  // N12: 보일 때만 재조회(가려진 탭·덮인 라우트는 재노출 시 1회).
  @override
  void onResumeRefresh() {
    _refresh();
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
    final String? studentId = _deps.auth.currentUserId;
    final Map<String, SubscriptionSummary> subs = studentId == null
        ? <String, SubscriptionSummary>{}
        : await _deps.subscriptions.fetchForStudent(studentId);
    final Map<String, MentorPublic> names =
        await _mentors.fetchMany(rooms.map((Room r) => r.mentorId));
    // A2: 멘토별 주간 사용량. ★ 한도값 재하드코딩 없이 RPC 반환만. 실패는 null(표시 생략).
    // C15: 멘토 수만큼 병렬 호출하던 것을 배치 RPC 1회로.
    final Map<String, WeeklyQuestionUsage?> usageByMentor = studentId == null
        ? <String, WeeklyQuestionUsage?>{}
        : await _repo.weeklyUsageBatch(rooms.map((Room r) => r.mentorId));
    // N37: 방별 실제 활동시각 — 스레드 슬림 조회 1회(방·상태·활동시각만).
    // 같은 조회에서 '답변 도착(answered)' 건수도 센다(§3-1 '답변 N' 배지).
    final Map<String, DateTime> lastByRoom = <String, DateTime>{};
    final Map<String, int> answeredByRoom = <String, int>{};
    try {
      final List<ThreadStatusRow> statusRows = await _repo
          .threadStatusRowsForRooms(rooms.map((Room r) => r.id).toList());
      for (final ThreadStatusRow t in statusRows) {
        final DateTime? cur = lastByRoom[t.roomId];
        if (cur == null || t.updatedAt.isAfter(cur)) {
          lastByRoom[t.roomId] = t.updatedAt;
        }
        if (t.status == ThreadStatus.answered) {
          answeredByRoom[t.roomId] = (answeredByRoom[t.roomId] ?? 0) + 1;
        }
      }
    } catch (_) {
      // 실패 시 방 updated_at 폴백(표시 저하일 뿐 흐름은 막지 않는다).
    }
    // §3-1: 멘토가 남긴 최근 노트 한 줄 — 방별 best-effort(실패·없음 = 미표시).
    final Map<String, ConnectionNote> noteByRoom = <String, ConnectionNote>{};
    await Future.wait(rooms.map((Room r) async {
      try {
        final List<ConnectionNote> notes = await _repo.notes(r.id);
        for (final ConnectionNote n in notes) {
          if (n.authorRole == NoteAuthorRole.mentor &&
              (n.body ?? '').trim().isNotEmpty) {
            noteByRoom[r.id] = n; // notes 는 최신순
            break;
          }
        }
      } catch (_) {
        // 노트는 보조 맥락 — 못 읽어도 목록은 그대로.
      }
    }));
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
              answeredCount: answeredByRoom[r.id] ?? 0,
              latestNote: noteByRoom[r.id],
            ))
        .toList();
    // N37: 표시·정렬 기준 통일 — 실제 활동시각 내림차순(인박스와 동일).
    items.sort(
        (_RoomItem a, _RoomItem b) => b.lastActivity.compareTo(a.lastActivity));
    return items;
  }

  void _refresh() {
    if (!mounted) return; // §4: dispose 후 setState 금지.
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            8,
            AppSpacing.screenH,
            12,
          ),
          child: AppInputField(
            hintText: '멘토 검색',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            onChanged: (String v) => setState(() => _query = v.trim()),
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
          return AppEmptyState(
            icon: Icons.cloud_off_rounded,
            title: '목록을 불러오지 못했어요',
            description: friendlyError(snap.error!),
          );
        }
        final List<_RoomItem> all = snap.data ?? <_RoomItem>[];
        if (all.isEmpty) {
          return Column(
            children: <Widget>[
              Expanded(
                child: AppEmptyState(
                  icon: Icons.forum_rounded,
                  title: '아직 질문방이 없어요',
                  description: '멘토를 구독하면 1:1 질문방이 열려요',
                  // CTA는 기존 탭 전환 경로만 재사용(멘토 찾기 탭). 결제 유도 아님.
                  actionLabel: '멘토 찾기',
                  onAction: () => TabNavigator.go(AppTab.mentors),
                ),
              ),
              Padding(
                padding: AppPage.contentPadding(context, top: 0, bottom: 16),
                child: const CommerceNoticeCard(text: kSubscribeNoticeText),
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
          return const AppEmptyState(
            icon: Icons.search_off,
            title: '검색 결과가 없어요',
            description: '다른 이름으로 검색해 보세요.',
          );
        }
        return ListView.separated(
          clipBehavior: Clip.none,
          padding: AppPage.contentPadding(context, top: 0),
          itemCount: items.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.listGap),
          itemBuilder: (BuildContext context, int i) =>
              _RoomTile(item: items[i], onOpen: () => _open(items[i])),
        );
      },
    );
  }

  Future<void> _open(_RoomItem it) async {
    await AppNavigation.push<void>(
      context,
      AppRoutePaths.room(it.room.id),
      fallbackBuilder: (_) => MentorRoomHomeScreen(
        room: it.room,
        mentorName: it.mentorName,
        sub: it.sub,
      ),
    );
    if (mounted) _refresh(); // 돌아오면 최신화(새 질문/확인 반영).
  }
}

/// 방 한 행(design-v3 §3-1): 아바타 · 이름 · 시각 / 요금제 · 이번 주 남은 질문 /
/// 📌 최근 노트 / 답변 N · 구독 상태 배지. 카드 하나가 방 하나.
class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.item, required this.onOpen});
  final _RoomItem item;
  final VoidCallback onOpen;

  /// '프리미엄 · 질문 무제한' / '스탠다드 · 이번 주 9개 중 9개 남았어요'.
  /// 요금제·한도 정보가 하나도 없으면 null(줄 생략 — 날조 금지).
  static String? planLine(
      SubscriptionSummary? sub, WeeklyQuestionUsage? usage) {
    final List<String> bits = <String>[];
    final String? tier = sub?.planTier?.trim();
    if (tier != null && tier.isNotEmpty) bits.add(planTierLabel(tier));
    final String? quota = SubscriptionCopy.quotaSentence(usage);
    if (quota != null) bits.add(quota);
    return bits.isEmpty ? null : bits.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final SubscriptionSummary? sub = item.sub;
    final String? plan = planLine(sub, item.usage);
    final ConnectionNote? note = item.latestNote;
    final String? noteSummary =
        note == null ? null : MentorNoteParts.parse(note.body).summary;

    // 상태 배지: 정상 이용(active)은 요금제 줄로 충분하다 — 해지 예정·만료·미결제
    // 처럼 학생이 알아야 할 상태만 배지로(§3-5 덧붙인 판단 ②).
    final Widget? statusBadge = _statusBadge(sub);
    final bool hasBadges = item.answeredCount > 0 || statusBadge != null;

    return GlassCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InitialAvatar(name: item.mentorName, size: 44, tinted: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.mentorName,
                        style: AppTypography.bodyStrong.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 마지막 활동시각 — N37: 방·스레드 max(인박스와 동일 기준).
                    Text(
                      Formatters.relativeKorean(item.lastActivity),
                      style: AppTypography.meta,
                    ),
                  ],
                ),
                if (plan != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    plan,
                    style: AppTypography.captionSecondary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (noteSummary != null && noteSummary.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  NotePreviewLine(summary: noteSummary),
                ],
                if (hasBadges) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      if (item.answeredCount > 0)
                        _SolidBadge(label: '답변 ${item.answeredCount}'),
                      if (statusBadge != null) statusBadge,
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 구독 상태 배지 — active 는 미표시. 해지 예정은 '해지 예정 · 9월 5일까지'.
  static Widget? _statusBadge(SubscriptionSummary? sub) {
    if (sub == null) return null;
    final String status = sub.status?.trim().toLowerCase() ?? '';
    if (status == 'active' && !sub.isCancelScheduled) return null;
    if (sub.isCancelScheduled) {
      final DateTime? until = sub.nextRenewal;
      return StatusPill(
        label:
            until == null ? '해지 예정' : '해지 예정 · ${Formatters.monthDay(until)}까지',
        tone: StatusTone.danger,
      );
    }
    if (status.isEmpty && sub.isActive) return null; // 미상 + 활성 → 정상 취급.
    final SubscriptionStatusDisplay disp =
        subscriptionStatusDisplay(sub.status, isActive: sub.isActive);
    return StatusPill(label: disp.label, tone: disp.tone);
  }
}

/// 역할색 채움 배지('답변 1' — design-v3 §3-1).
class _SolidBadge extends StatelessWidget {
  const _SolidBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: RoleTheme.of(context).color,
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        label,
        style: AppTypography.meta.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}
