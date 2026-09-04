import 'package:flutter/material.dart';

import '../../../../app/app_navigation.dart';
import '../../../../app/app_route_paths.dart';
import '../../../../app/app_scope.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/shape_tokens.dart';
import '../../../../design/spacing_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/app_card.dart';
import '../../../../design/widgets/empty_state.dart';
import '../../../../design/widgets/initial_avatar.dart';
import '../../../../design/widgets/status_pill.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/models/room.dart';
import '../../data/question_room_read_repository.dart';
import '../../data/student_lookup_repository.dart';
import '../../data/thread_status_counts.dart';
import 'student_room_home_screen.dart';
import '../../../../core/refresh/data_refresh_bus.dart';
import '../../../../shared/errors/friendly_error.dart';
import '../../../../shared/widgets/screen_visibility.dart';

/// 멘토 질문방 1뎁스 = '받은 학생' 목록(카카오톡식 리스트). 본문만(셸이 AppBar/탭 제공).
///
/// 각 행: 학생 이니셜아바타(+답할 게 있으면 주의 점) · 학생명 · 상태요약 · 마지막 활동.
/// 상단 검색(학생명). RLS상 myRooms()는 멘토 본인의 방(mentor_id=나)만 돌려준다 — S4 재사용.
class MentorInboxScreen extends StatefulWidget {
  const MentorInboxScreen({super.key});

  @override
  State<MentorInboxScreen> createState() => _MentorInboxScreenState();
}

/// 행 묶음(방 + 학생 표시명 + 상태 집계 + 마지막 활동).
class _StudentItem {
  const _StudentItem({
    required this.room,
    this.student,
    required this.counts,
    required this.lastActivity,
  });

  final Room room;
  final StudentPublic? student;
  final ThreadStatusCounts counts;
  final DateTime lastActivity;

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
    // 학생 표시명 조회는 스레드 조회와 독립 — 병렬.
    final List<dynamic> loaded = await Future.wait(<Future<dynamic>>[
      _repo.threadStatusRowsForRooms(roomIds),
      _students.fetchMany(rooms.map((Room r) => r.studentId)),
    ]);
    final List<ThreadStatusRow> statusRows = loaded[0] as List<ThreadStatusRow>;
    final Map<String, StudentPublic> names =
        loaded[1] as Map<String, StudentPublic>;

    final Map<String, List<ThreadStatusRow>> byRoom =
        <String, List<ThreadStatusRow>>{};
    for (final ThreadStatusRow t in statusRows) {
      (byRoom[t.roomId] ??= <ThreadStatusRow>[]).add(t);
    }

    return <_StudentItem>[
      for (final Room r in rooms)
        _StudentItem(
          room: r,
          student: names[r.studentId],
          counts: ThreadStatusCounts.fromStatuses(
              (byRoom[r.id] ?? const <ThreadStatusRow>[])
                  .map((ThreadStatusRow t) => t.status)),
          lastActivity: _lastActivity(byRoom[r.id], r),
        ),
    ];
  }

  DateTime _lastActivity(List<ThreadStatusRow>? threads, Room room) {
    DateTime last = room.updatedAt;
    for (final ThreadStatusRow t in threads ?? const <ThreadStatusRow>[]) {
      if (t.updatedAt.isAfter(last)) last = t.updatedAt;
    }
    return last;
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH, 12, AppSpacing.screenH, 8),
          child: TextField(
            style: AppType.body,
            onChanged: (String v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: '학생 검색',
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
      ],
    );
  }

  Widget _list() {
    return FutureBuilder<List<_StudentItem>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<_StudentItem>> snap) {
        // R1(20건 리뷰): future 교체형 새로고침(N35 탭 신호·resume) 동안
        // 이전 데이터가 스냅샷에 유지되므로, 데이터가 있으면 스피너 대신
        // 기존 목록을 계속 보여준다(탭 전환마다 번쩍임 제거).
        if (snap.connectionState != ConnectionState.done && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '학생 목록을 불러오지 못했어요.\n${friendlyError(snap.error!)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: ColorTokens.danger),
              ),
            ),
          );
        }
        final List<_StudentItem> all = snap.data ?? <_StudentItem>[];
        if (all.isEmpty) {
          return const EmptyState(
            icon: Icons.forum_rounded,
            title: '아직 받은 학생이 없어요',
            message: '학생이 구독하면 여기에서 질문에 답할 수 있어요.',
          );
        }
        final List<_StudentItem> items = _query.isEmpty
            ? all
            : all
                .where((_StudentItem it) => it.studentName.contains(_query))
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
              AppSpacing.screenH, 4, AppSpacing.screenH, 12),
          itemCount: items.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.cardGap),
          itemBuilder: (BuildContext context, int i) =>
              _StudentTile(item: items[i], onOpen: () => _open(items[i])),
        );
      },
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
    return AppCard(
      onTap: onOpen,
      child: Row(
        children: <Widget>[
          _AvatarWithDot(name: item.studentName, dot: c.needsAttention),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(item.studentName, style: AppType.body),
                const SizedBox(height: 6),
                // 상태 카운트를 StatusDot + 개수로 시각화(현재 텍스트만이던 것).
                _statusChips(context, c),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Formatters.relativeKorean(item.lastActivity),
            style: AppType.caption,
          ),
        ],
      ),
    );
  }

  /// 상태 카운트 시각화(StatusDot + 개수). 값은 ThreadStatusCounts(이미 집계) — 새 조회 없음.
  Widget _statusChips(BuildContext context, ThreadStatusCounts c) {
    if (c.total == 0) {
      return Text('질문 없음', style: AppType.caption);
    }
    final List<Widget> chips = <Widget>[
      if (c.pending > 0)
        _dotCount(context, StatusTone.warning, '답변 대기 ${c.pending}'),
      if (c.inProgress > 0)
        _dotCount(context, StatusTone.info, '진행 중 ${c.inProgress}'),
    ];
    if (chips.isEmpty) {
      chips.add(_dotCount(context, StatusTone.success, '모두 답변 완료'));
    }
    return Wrap(spacing: 12, runSpacing: 4, children: chips);
  }

  /// StatusDot(색) + 개수 텍스트 한 쌍(StatusDot 재사용 — 새 위젯 아님).
  Widget _dotCount(BuildContext context, StatusTone tone, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        StatusDot(tone: tone),
        const SizedBox(width: 5),
        Text(
          text,
          style: AppType.caption.copyWith(
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
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          InitialAvatar(name: name, size: 48),
          if (dot)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: ColorTokens.warning,
                  shape: BoxShape.circle,
                  border: Border.all(color: ColorTokens.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
