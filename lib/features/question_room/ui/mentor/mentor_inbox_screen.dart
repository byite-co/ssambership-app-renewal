import 'package:flutter/material.dart';

import '../../../../app/app_navigation.dart';
import '../../../../app/app_route_paths.dart';
import '../../../../app/app_scope.dart';
import '../../../../core/refresh/data_refresh_bus.dart';
import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_spacing.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/app_blocks.dart';
import '../../../../design/widgets/app_empty_state.dart';
import '../../../../design/widgets/app_input_field.dart';
import '../../../../design/widgets/app_page.dart';
import '../../../../design/widgets/glass_card.dart';
import '../../../../design/widgets/initial_avatar.dart';
import '../../../../design/widgets/status_pill.dart';
import '../../../../shared/errors/friendly_error.dart';
import '../../../../shared/format/formatters.dart';
import '../../../../shared/widgets/screen_visibility.dart';
import '../../data/mentor_note_format.dart';
import '../../data/models/connection_note.dart';
import '../../data/models/room.dart';
import '../../data/question_room_read_repository.dart';
import '../../data/student_lookup_repository.dart';
import '../../data/thread_status_counts.dart';
import '../widgets/note_preview_line.dart';
import 'student_room_home_screen.dart';

/// 멘토 질문방 1뎁스 = '받은 학생' 목록(design-v3 §4-1). 본문만(셸이 AppBar/탭 제공).
///
/// 상단에 오늘 할 일 한 문장, 답변 대기가 있는 방이 항상 위(정렬 옵션 없음 — §7).
/// 각 행: 학생 이니셜아바타(+답할 게 있으면 주의 점) · 학생명 · 마지막 활동 ·
/// 내가 남긴 최근 노트 한 줄 · 답변 대기 배지. RLS상 myRooms()는 멘토 본인의
/// 방(mentor_id=나)만 돌려준다 — S4 재사용.
class MentorInboxScreen extends StatefulWidget {
  const MentorInboxScreen({super.key});

  @override
  State<MentorInboxScreen> createState() => _MentorInboxScreenState();
}

/// 행 묶음(방 + 학생 표시명 + 상태 집계 + 마지막 활동 + 최근 노트).
class _StudentItem {
  const _StudentItem({
    required this.room,
    this.student,
    required this.counts,
    required this.lastActivity,
    this.latestNote,
  });

  final Room room;
  final StudentPublic? student;
  final ThreadStatusCounts counts;
  final DateTime lastActivity;

  /// 이 방에 내가(멘토) 마지막으로 남긴 노트. 없으면 null.
  final ConnectionNote? latestNote;

  String get studentName => student?.displayName ?? '학생';
}

class _MentorInboxScreenState extends State<MentorInboxScreen>
    with WidgetsBindingObserver, ResumeVisibilityGate {
  // A-2: 레포지토리는 AppScope 에서 받는다(직접 생성 0).
  late final AppDependencies _deps;
  QuestionRoomReadRepository get _repo => _deps.questionRoomRead;
  StudentLookupRepository get _students => _deps.studentLookup;

  late Future<List<_StudentItem>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _deps = AppScope.of(context);
    _future = _load();
    // N33: 학생 탭(질문방 목록)은 resume 재조회가 있는데 멘토 인박스는 없어
    // 같은 질문방 탭이 역할에 따라 신선도가 달랐다 — 동일 패턴으로 정렬.
    WidgetsBinding.instance.addObserver(this);
    // N35: 탭 전환·재선택 등 질문방 표면 신호 수신(학생 목록과 동일 배선).
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

  Future<List<_StudentItem>> _load() async {
    final List<Room> rooms = await _repo.myRooms();
    if (rooms.isEmpty) return <_StudentItem>[];

    final List<String> roomIds = rooms.map((Room r) => r.id).toList();
    // N20: 집계에 필요한 방·상태·활동시각만 슬림 조회(제목·본문 전량 수신 제거).
    // 학생 표시명 조회는 스레드 조회와 독립 — 병렬. 최근 노트(§4-1 '📌')는
    // 방마다 best-effort(실패해도 목록은 막지 않는다).
    final List<dynamic> loaded = await Future.wait(<Future<dynamic>>[
      _repo.threadStatusRowsForRooms(roomIds),
      _students.fetchMany(rooms.map((Room r) => r.studentId)),
      Future.wait(rooms.map((Room r) => _latestMyNote(r.id))),
    ]);
    final List<ThreadStatusRow> statusRows = loaded[0] as List<ThreadStatusRow>;
    final Map<String, StudentPublic> names =
        loaded[1] as Map<String, StudentPublic>;
    final List<ConnectionNote?> notes = loaded[2] as List<ConnectionNote?>;

    final Map<String, List<ThreadStatusRow>> byRoom =
        <String, List<ThreadStatusRow>>{};
    for (final ThreadStatusRow t in statusRows) {
      (byRoom[t.roomId] ??= <ThreadStatusRow>[]).add(t);
    }

    final List<_StudentItem> items = <_StudentItem>[
      for (int i = 0; i < rooms.length; i++)
        _StudentItem(
          room: rooms[i],
          student: names[rooms[i].studentId],
          counts: ThreadStatusCounts.fromStatuses(
              (byRoom[rooms[i].id] ?? const <ThreadStatusRow>[])
                  .map((ThreadStatusRow t) => t.status)),
          lastActivity: _lastActivity(byRoom[rooms[i].id], rooms[i]),
          latestNote: notes[i],
        ),
    ];
    // §4-1·§7: 답변 대기가 있는 방이 항상 위(대기 많은 순) → 그다음 최근 활동순.
    items.sort((_StudentItem a, _StudentItem b) {
      final int byPending = b.counts.pending.compareTo(a.counts.pending);
      if (byPending != 0) return byPending;
      return b.lastActivity.compareTo(a.lastActivity);
    });
    return items;
  }

  /// 이 방에서 내가 남긴 최근 노트(notes 는 최근순). 조회 실패 → null.
  Future<ConnectionNote?> _latestMyNote(String roomId) async {
    try {
      final String? uid = _deps.auth.currentUserId;
      final List<ConnectionNote> notes = await _repo.notes(roomId);
      for (final ConnectionNote n in notes) {
        final bool mine = uid != null && n.authorId == uid;
        if (mine || (uid == null && n.authorRole == NoteAuthorRole.mentor)) {
          return n;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  DateTime _lastActivity(List<ThreadStatusRow>? threads, Room room) {
    DateTime last = room.updatedAt;
    for (final ThreadStatusRow t in threads ?? const <ThreadStatusRow>[]) {
      if (t.updatedAt.isAfter(last)) last = t.updatedAt;
    }
    return last;
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_StudentItem>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<_StudentItem>> snap) {
        // R1(20건 리뷰): future 교체형 새로고침(N35 탭 신호·resume) 동안
        // 이전 데이터가 스냅샷에 유지되므로, 데이터가 있으면 스피너 대신
        // 기존 목록을 계속 보여준다(탭 전환마다 번쩍임 제거).
        final List<_StudentItem>? all = snap.data;
        final int pending = all == null
            ? 0
            : all.fold<int>(
                0, (int acc, _StudentItem it) => acc + it.counts.pending);
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH, 8, AppSpacing.screenH, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (all != null && all.isNotEmpty) ...<Widget>[
                    Text(
                      pending > 0
                          ? '오늘 답변할 질문 $pending개가 있어요'
                          : '지금 답변할 질문이 없어요',
                      style: AppTypography.section,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                  ],
                  AppInputField(
                    hintText: '학생 검색',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.textSecondary),
                    onChanged: (String v) => setState(() => _query = v.trim()),
                  ),
                ],
              ),
            ),
            Expanded(child: _list(snap)),
          ],
        );
      },
    );
  }

  Widget _list(AsyncSnapshot<List<_StudentItem>> snap) {
    if (snap.connectionState != ConnectionState.done && !snap.hasData) {
      return const AppLoadingView();
    }
    if (snap.hasError) {
      return AppErrorView(
        title: '학생 목록을 불러오지 못했어요',
        message: friendlyError(snap.error!),
        onRetry: _refresh,
      );
    }
    final List<_StudentItem> all = snap.data ?? <_StudentItem>[];
    if (all.isEmpty) {
      return const AppEmptyState(
        icon: Icons.forum_rounded,
        title: '아직 받은 학생이 없어요',
        description: '학생이 구독하면 여기에서 질문에 답할 수 있어요.',
      );
    }
    final List<_StudentItem> items = _query.isEmpty
        ? all
        : all
            .where((_StudentItem it) => it.studentName.contains(_query))
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
      padding: AppPage.contentPadding(context, top: 4),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.listGap),
      itemBuilder: (BuildContext context, int i) =>
          _StudentTile(item: items[i], onOpen: () => _open(items[i])),
    );
  }

  Future<void> _open(_StudentItem it) async {
    await AppNavigation.push<void>(
      context,
      AppRoutePaths.room(it.room.id),
      fallbackBuilder: (_) => StudentRoomHomeScreen(
        room: it.room,
        studentName: it.studentName,
      ),
    );
    if (mounted) _refresh(); // 돌아오면 최신화(답변/상태 반영).
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({required this.item, required this.onOpen});
  final _StudentItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ThreadStatusCounts c = item.counts;
    final String? note = item.latestNote?.body;
    final String? noteSummary = note == null || note.trim().isEmpty
        ? null
        : MentorNoteParts.parse(note).summary;
    return GlassCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _AvatarWithDot(name: item.studentName, dot: c.needsAttention),
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
                        item.studentName,
                        style: AppTypography.bodyStrong.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      Formatters.relativeKorean(item.lastActivity),
                      style: AppTypography.meta,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (noteSummary != null)
                  NotePreviewLine(summary: noteSummary)
                else
                  const Text('노트 없음', style: AppTypography.meta),
                const SizedBox(height: 8),
                // 상태 카운트(StatusDot + 개수). 값은 ThreadStatusCounts — 새 조회 없음.
                _statusChips(context, c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChips(BuildContext context, ThreadStatusCounts c) {
    if (c.total == 0) {
      return const Text('질문 없음', style: AppTypography.captionSecondary);
    }
    final List<Widget> chips = <Widget>[
      if (c.pending > 0)
        StatusPill(label: '답변 대기 ${c.pending}', tone: StatusTone.warning),
      if (c.inProgress > 0)
        _dotCount(context, StatusTone.info, '진행 중 ${c.inProgress}'),
    ];
    if (chips.isEmpty) {
      chips.add(_dotCount(context, StatusTone.success, '모두 답변 완료'));
    }
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }

  /// StatusDot(색) + 개수 텍스트 한 쌍.
  Widget _dotCount(BuildContext context, StatusTone tone, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        StatusDot(tone: tone),
        const SizedBox(width: 5),
        Text(
          text,
          style: AppTypography.caption.copyWith(
            color: statusToneColor(context, tone),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 이니셜 아바타 + (답할 게 있으면) 우상단 주의 점.
class _AvatarWithDot extends StatelessWidget {
  const _AvatarWithDot({required this.name, required this.dot});
  final String name;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          InitialAvatar(name: name, size: 44, tinted: false),
          if (dot)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.glass, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
