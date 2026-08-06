import 'package:flutter/material.dart';

import '../../../../core/entitlement/subscription_summary.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/spacing_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/status_pill.dart';
import '../../../../shared/format/formatters.dart';
import '../../data/models/connection_note.dart';
import '../../data/models/question_thread.dart';
import '../../data/models/room.dart';
import '../../data/question_room_read_repository.dart';
import '../../data/thread_status_counts.dart';
import '../connection_notes_screen.dart';
import '../widgets/entrance_card.dart';
import '../widgets/thread_status_pill.dart';
import 'mentor_question_list_screen.dart';
import '../../../../shared/errors/friendly_error.dart';

/// 멘토 질문방 2뎁스 = 학생방 홈. S4 멘토방 홈의 거울상(멘토 시점).
///
/// 얇은 헤더(학생명 · 구독 상태) + 동등한 두 입구:
///  ① 질문 / 답변 — 답변 대기 건수 + 최근 질문 미리보기.
///  ② 연결노트 — 내(멘토) 노트 최근 1줄 + 학생 메모 미리보기.
class StudentRoomHomeScreen extends StatefulWidget {
  const StudentRoomHomeScreen({
    super.key,
    required this.room,
    required this.studentName,
  });

  final Room room;
  final String studentName;

  @override
  State<StudentRoomHomeScreen> createState() => _StudentRoomHomeScreenState();
}

class _StudentRoomHomeScreenState extends State<StudentRoomHomeScreen> {
  final QuestionRoomReadRepository _repo = const QuestionRoomReadRepository();
  late Future<_StudentHomeData> _future;

  String? get _uid => SupabaseInit.clientOrNull?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_StudentHomeData> _load() async {
    final List<QuestionThread> threads = await _repo.threads(widget.room.id);
    final List<ConnectionNote> notes = await _repo.notes(widget.room.id);

    ConnectionNote? myNote; // 멘토 본인 노트(author_id == 나)
    ConnectionNote? studentNote; // 학생 노트
    for (final ConnectionNote n in notes) {
      final bool mine = _uid != null && n.authorId == _uid;
      if (mine) {
        myNote ??= n;
      } else if (n.authorRole == NoteAuthorRole.student) {
        studentNote ??= n;
      }
    }

    // 구독 상태(표시만). N38: '첫 요약'(values.first) 임의 선택 대신 이 방의
    // 멘토와 매칭되는 요약을 쓴다 — 다중 구독 학생에서 남의 구독 오표시 제거
    // (멘토 RLS 는 자기 pair 행만 통과하지만, 키 매칭이 정본이다).
    SubscriptionSummary? sub;
    final client = SupabaseInit.clientOrNull;
    if (client != null) {
      final Map<String, SubscriptionSummary> subs =
          await SubscriptionReader.fetchForStudent(client, widget.room.studentId);
      sub = subs[widget.room.mentorId];
    }

    return _StudentHomeData(
      counts: ThreadStatusCounts.from(threads),
      latestThread: threads.isNotEmpty ? threads.first : null,
      myNote: myNote,
      studentNote: studentNote,
      sub: sub,
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.studentName)),
      body: FutureBuilder<_StudentHomeData>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<_StudentHomeData> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('불러오지 못했어요.\n${friendlyError(snap.error!)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ColorTokens.danger)),
              ),
            );
          }
          final _StudentHomeData d = snap.data!;
          // 학생 이름은 AppBar 제목에 이미 있으므로 본문 헤더에서는 중복 표시하지 않는다.
          final Widget? header = _header(d.sub);
          return ListView(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH, vertical: AppSpacing.s16),
            children: <Widget>[
              if (header != null) ...<Widget>[
                header,
                const SizedBox(height: AppSpacing.section),
              ],
              EntranceCard(
                icon: Icons.forum_rounded,
                title: '질문 / 답변',
                trailing: d.counts.pending > 0
                    ? StatusPill(
                        label: '답변 대기 ${d.counts.pending}',
                        tone: StatusTone.warning,
                      )
                    : null,
                onTap: _openQuestions,
                child: d.latestThread == null
                    ? Text('아직 받은 질문이 없어요.', style: AppType.caption)
                    : Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _threadTitle(d.latestThread!),
                              style: AppType.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ThreadStatusPill(status: d.latestThread!.status),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              EntranceCard(
                icon: Icons.sticky_note_2_outlined,
                title: '연결노트',
                onTap: _openNotes,
                child: _notesPreview(d),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 구독 상태 한 줄(학생 이름은 AppBar 제목과 중복이라 제외). 표시할 게 없으면 null.
  Widget? _header(SubscriptionSummary? sub) {
    final List<String> bits = <String>[
      if (sub != null) (sub.isActive ? '구독 중' : '구독 만료'),
      if (sub?.nextRenewal != null)
        '다음 갱신 ${Formatters.shortDate(sub!.nextRenewal!)}',
    ];
    if (bits.isEmpty) return null;
    return Text(bits.join(' · '), style: AppType.caption);
  }

  Widget _notesPreview(_StudentHomeData d) {
    final String? mine = d.myNote?.body?.trim();
    final String? stu = d.studentNote?.body?.trim();
    if ((mine == null || mine.isEmpty) && (stu == null || stu.isEmpty)) {
      return Text('아직 노트가 없어요. 내 노트를 추가해 보세요.',
          style: AppType.caption);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (mine != null && mine.isNotEmpty) ...<Widget>[
          Text('내 노트', style: AppType.caption),
          const SizedBox(height: 2),
          Text(mine,
              style: AppType.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
        if (stu != null && stu.isNotEmpty) ...<Widget>[
          if (mine != null && mine.isNotEmpty) const SizedBox(height: 8),
          Text('학생 메모', style: AppType.caption),
          const SizedBox(height: 2),
          Text(stu,
              style: AppType.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }

  String _threadTitle(QuestionThread t) =>
      t.title?.trim().isNotEmpty == true ? t.title!.trim() : '(제목 없음)';

  Future<void> _openQuestions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MentorQuestionListScreen(
          room: widget.room,
          studentName: widget.studentName,
        ),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _openNotes() async {
    // S4 연결노트 화면 재사용 — 역할 무관(본인 author 행만 추가/수정).
    // 멘토에겐 '상대 노트'=학생, '내 노트'=멘토로 자연스럽게 매핑된다.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConnectionNotesScreen(
          room: widget.room,
          mentorName: widget.studentName,
        ),
      ),
    );
    if (mounted) _refresh();
  }
}

class _StudentHomeData {
  const _StudentHomeData({
    required this.counts,
    this.latestThread,
    this.myNote,
    this.studentNote,
    this.sub,
  });
  final ThreadStatusCounts counts;
  final QuestionThread? latestThread;
  final ConnectionNote? myNote;
  final ConnectionNote? studentNote;
  final SubscriptionSummary? sub;
}
