import 'package:flutter/material.dart';

import '../../../../app/app_navigation.dart';
import '../../../../app/app_route_paths.dart';
import '../../../../data/mappings/subject_labels.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/spacing_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/chip_scroll.dart';
import '../../../../design/widgets/empty_state.dart';
import '../../data/models/question_thread.dart';
import '../../data/models/room.dart';
import '../../data/question_room_read_repository.dart';
import '../../data/thread_status_counts.dart';
import '../widgets/thread_card.dart';
import 'mentor_answer_screen.dart';
import '../../../../shared/errors/friendly_error.dart';

/// 멘토 질문 목록(3뎁스). ★ 멘토 고유: 상태 탭(전체 / 답변 대기 / 진행 중 / 완료) + 과목 필터 + 정렬.
/// 기본 선택은 '전체' — 과거 기록이 첫 진입에서 바로 보인다(답변 대기 기본값이
/// 기존 기록을 숨겨 보이던 문제 제거). 카드는 S4 ThreadCard 재사용. 카드 탭 → 답변 화면.
class MentorQuestionListScreen extends StatefulWidget {
  const MentorQuestionListScreen({
    super.key,
    required this.room,
    required this.studentName,
    this.readRepository = const QuestionRoomReadRepository(),
  });

  final Room room;
  final String studentName;

  /// 테스트 주입 지점(기본: 운영 레포) — NewQuestionScreen 과 동일 패턴.
  final QuestionRoomReadRepository readRepository;

  @override
  State<MentorQuestionListScreen> createState() =>
      _MentorQuestionListScreenState();
}

/// 상태 탭. 라벨/색은 ThreadStatusPill·라벨 유틸과 동일 매핑.
/// 전체=모든 상태(unknown 포함), 답변 대기=pending, 진행 중=answered/open,
/// 완료=confirmed/closed/archived. 알 수 없는 상태는 전체 탭에서만 보인다.
enum _StatusTab { all, pending, inProgress, done }

class _MentorQuestionListScreenState extends State<MentorQuestionListScreen> {
  QuestionRoomReadRepository get _read => widget.readRepository;

  late Future<List<QuestionThread>> _future;
  _StatusTab _tab = _StatusTab.all; // 첫 진입 = 전체(기존 기록 노출).
  String? _subjectCode; // null = 전체
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    _future = _read.threads(widget.room.id);
  }

  void _refresh() => setState(() => _future = _read.threads(widget.room.id));

  bool _matchesTab(QuestionThread t) {
    switch (_tab) {
      case _StatusTab.all:
        return true; // 조회된 모든 질문(unknown 상태 포함).
      case _StatusTab.pending:
        return t.status == ThreadStatus.pending;
      case _StatusTab.inProgress:
        return t.status == ThreadStatus.answered ||
            t.status == ThreadStatus.open;
      case _StatusTab.done:
        return t.status == ThreadStatus.confirmed ||
            t.status == ThreadStatus.closed ||
            t.status == ThreadStatus.archived;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(widget.studentName,
                style: AppType.caption.copyWith(color: ColorTokens.muted)),
            Text('질문 / 답변', style: AppType.body),
          ],
        ),
      ),
      body: FutureBuilder<List<QuestionThread>>(
        future: _future,
        builder:
            (BuildContext context, AsyncSnapshot<List<QuestionThread>> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('질문을 불러오지 못했어요.\n${friendlyError(snap.error!)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ColorTokens.danger)),
              ),
            );
          }
          final List<QuestionThread> all = snap.data ?? <QuestionThread>[];
          final ThreadStatusCounts counts = ThreadStatusCounts.from(all);

          // 과목 옵션(전체 + 데이터에 존재하는 과목 코드).
          final List<String> subjectCodes = <String>[];
          for (final QuestionThread t in all) {
            final String? c = t.subject;
            if (c != null && c.trim().isNotEmpty && !subjectCodes.contains(c)) {
              subjectCodes.add(c);
            }
          }

          // 필터 + 정렬.
          final List<QuestionThread> visible = all.where((QuestionThread t) {
            if (!_matchesTab(t)) return false;
            if (_subjectCode != null && t.subject != _subjectCode) return false;
            return true;
          }).toList()
            ..sort((QuestionThread a, QuestionThread b) => _newestFirst
                ? b.updatedAt.compareTo(a.updatedAt)
                : a.updatedAt.compareTo(b.updatedAt));

          // stretch: 두 필터 줄이 모두 전체 폭을 채워 같은 좌측 기준으로 정렬되도록
          // (기본 center면 상태칩 줄이 콘텐츠 폭으로 줄어 가운데로 쏠려 과목칩 줄과 어긋난다).
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _statusTabs(counts),
              _filterBar(subjectCodes),
              const Divider(height: 1, color: ColorTokens.border),
              Expanded(child: _list(visible, all.isEmpty)),
            ],
          );
        },
      ),
    );
  }

  Widget _statusTabs(ThreadStatusCounts c) {
    final List<String> labels = <String>[
      '전체 ${c.total}',
      '답변 대기 ${c.pending}',
      '진행 중 ${c.inProgress}',
      '완료 ${c.completed}',
    ];
    // 아래 과목 필터 줄과 좌우 기준·줄 간격을 통일(같은 LTRB 프레임, 대칭 세로 간격).
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 6),
      child: ChipScroll(
        labels: labels,
        selectedIndex: _StatusTab.values.indexOf(_tab),
        onSelected: (int i) => setState(() => _tab = _StatusTab.values[i]),
      ),
    );
  }

  Widget _filterBar(List<String> subjectCodes) {
    // [전체] + 과목들. 인덱스 0 = 전체(null).
    final List<String> labels = <String>[
      '전체',
      for (final String code in subjectCodes) subjectLabel(code),
    ];
    final int selected =
        _subjectCode == null ? 0 : subjectCodes.indexOf(_subjectCode!) + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ChipScroll(
              labels: labels,
              selectedIndex: selected < 0 ? 0 : selected,
              onSelected: (int i) => setState(() {
                _subjectCode = i == 0 ? null : subjectCodes[i - 1];
              }),
            ),
          ),
          IconButton(
            tooltip: _newestFirst ? '최신순' : '오래된순',
            icon: Icon(
              _newestFirst
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: ColorTokens.secondary,
              size: 20,
            ),
            onPressed: () => setState(() => _newestFirst = !_newestFirst),
          ),
        ],
      ),
    );
  }

  Widget _list(List<QuestionThread> visible, bool noThreadsAtAll) {
    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: noThreadsAtAll ? '아직 받은 질문이 없어요' : '이 조건의 질문이 없어요',
        message: noThreadsAtAll ? '학생이 질문하면 여기에 표시돼요.' : '다른 탭이나 과목을 선택해 보세요.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, 12, AppSpacing.screenH, 16),
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
      itemBuilder: (BuildContext context, int i) => ThreadCard(
        thread: visible[i],
        onOpen: () => _openAnswer(visible[i]),
      ),
    );
  }

  Future<void> _openAnswer(QuestionThread t) async {
    await AppNavigation.push<void>(
      context,
      AppRoutePaths.roomThread(widget.room.id, t.id),
      fallbackBuilder: (_) => MentorAnswerScreen(
        thread: t,
        studentName: widget.studentName,
        room: widget.room, // 신고·차단 상대 도출의 정본(참여자 데이터).
      ),
    );
    if (mounted) _refresh(); // 답변/상태 전이 반영.
  }
}
