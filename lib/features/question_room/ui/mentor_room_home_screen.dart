import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_route_paths.dart';
import '../../../core/entitlement/subscription_summary.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/typography_tokens.dart';
import '../../../shared/format/formatters.dart';
import '../data/models/connection_note.dart';
import '../data/models/question_thread.dart';
import '../data/models/room.dart';
import '../data/question_room_read_repository.dart';
import 'connection_notes_screen.dart';
import 'question_list_screen.dart';
import 'widgets/entrance_card.dart';
import 'widgets/thread_status_pill.dart';
import '../../../shared/errors/friendly_error.dart';

/// 멘토방 홈(2뎁스). 얇은 헤더 + 동등한 두 입구(질문/답변·연결노트) 미리보기.
class MentorRoomHomeScreen extends StatefulWidget {
  const MentorRoomHomeScreen({
    super.key,
    required this.room,
    required this.mentorName,
    this.sub,
  });

  final Room room;
  final String mentorName;
  final SubscriptionSummary? sub;

  @override
  State<MentorRoomHomeScreen> createState() => _MentorRoomHomeScreenState();
}

class _MentorRoomHomeScreenState extends State<MentorRoomHomeScreen> {
  final QuestionRoomReadRepository _repo = const QuestionRoomReadRepository();
  late Future<_RoomHomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RoomHomeData> _load() async {
    final List<QuestionThread> threads = await _repo.threads(widget.room.id);
    final List<ConnectionNote> notes = await _repo.notes(widget.room.id);
    QuestionThread? latestThread = threads.isNotEmpty ? threads.first : null;
    ConnectionNote? latestMentorNote;
    for (final ConnectionNote n in notes) {
      if (n.authorRole == NoteAuthorRole.mentor) {
        latestMentorNote = n;
        break; // notes 는 최근 수정순
      }
    }
    return _RoomHomeData(
      threadCount: threads.length,
      latestThread: latestThread,
      latestMentorNote: latestMentorNote,
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.mentorName)),
      body: FutureBuilder<_RoomHomeData>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<_RoomHomeData> snap) {
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
          final _RoomHomeData d = snap.data!;
          return ListView(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH, vertical: AppSpacing.s16),
            children: <Widget>[
              _header(),
              const SizedBox(height: AppSpacing.section),
              EntranceCard(
                icon: Icons.forum_rounded,
                title: '질문 / 답변',
                child: d.latestThread == null
                    ? Text('아직 질문이 없어요. 첫 질문을 남겨보세요.', style: AppType.caption)
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
                onTap: () => _openQuestions(),
              ),
              const SizedBox(height: 12),
              EntranceCard(
                icon: Icons.sticky_note_2_outlined,
                title: '연결노트',
                child: d.latestMentorNote?.body?.trim().isNotEmpty == true
                    ? Text(
                        d.latestMentorNote!.body!.trim(),
                        style: AppType.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text('멘토가 남긴 노트가 아직 없어요.', style: AppType.caption),
                onTap: () => _openNotes(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header() {
    final SubscriptionSummary? sub = widget.sub;
    final List<String> bits = <String>[
      if (sub != null) (sub.isActive ? '구독 중' : '구독 만료'),
      if (sub?.nextRenewal != null)
        '다음 갱신 ${Formatters.shortDate(sub!.nextRenewal!)}',
    ];
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(widget.mentorName, style: AppType.title),
        ),
        if (bits.isNotEmpty) Text(bits.join(' · '), style: AppType.caption),
      ],
    );
  }

  String _threadTitle(QuestionThread t) =>
      t.title?.trim().isNotEmpty == true ? t.title!.trim() : '(제목 없음)';

  Future<void> _openQuestions() async {
    await AppNavigation.push<void>(
      context,
      AppRoutePaths.roomThreads(widget.room.id),
      fallbackBuilder: (_) => QuestionListScreen(
        room: widget.room,
        mentorName: widget.mentorName,
        sub: widget.sub,
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _openNotes() async {
    await AppNavigation.push<void>(
      context,
      AppRoutePaths.roomNotes(widget.room.id),
      fallbackBuilder: (_) => ConnectionNotesScreen(
        room: widget.room,
        mentorName: widget.mentorName,
      ),
    );
    if (mounted) _refresh();
  }
}

class _RoomHomeData {
  const _RoomHomeData({
    required this.threadCount,
    this.latestThread,
    this.latestMentorNote,
  });
  final int threadCount;
  final QuestionThread? latestThread;
  final ConnectionNote? latestMentorNote;
}
