import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_route_paths.dart';
import '../../../app/app_scope.dart';
import '../../../core/entitlement/subscription_summary.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_blocks.dart';
import '../../../design/widgets/app_page.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/labels/subscription_copy.dart';
import '../data/models/connection_note.dart';
import '../data/models/question_thread.dart';
import '../data/models/room.dart';
import '../data/question_room_read_repository.dart';
import 'connection_notes_screen.dart';
import 'question_list_screen.dart';
import 'widgets/entrance_card.dart';
import 'widgets/thread_status_pill.dart';

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
  late final AppDependencies _dependencies;
  QuestionRoomReadRepository get _repo => _dependencies.questionRoomRead;
  late Future<_RoomHomeData> _future;

  @override
  void initState() {
    super.initState();
    _dependencies = AppScope.of(context);
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
    return AppPage(
      title: widget.mentorName,
      body: FutureBuilder<_RoomHomeData>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<_RoomHomeData> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppLoadingView(cards: 2);
          }
          if (snap.hasError) {
            return AppErrorView(
              message: friendlyError(snap.error!),
              onRetry: _refresh,
            );
          }
          final _RoomHomeData d = snap.data!;
          final String? header =
              SubscriptionCopy.subscriptionSentence(widget.sub);
          return ListView(
            clipBehavior: Clip.none,
            padding: AppPage.contentPadding(context),
            children: <Widget>[
              // 멘토 이름은 앱바 제목에 있으므로 본문에는 구독 문장만 둔다.
              if (header != null) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                  child: Text(header, style: AppTypography.captionSecondary),
                ),
                const SizedBox(height: AppSpacing.s12),
              ],
              EntranceCard(
                icon: Icons.forum_rounded,
                title: '질문 / 답변',
                child: d.latestThread == null
                    ? const Text('아직 질문이 없어요. 첫 질문을 남겨보세요.',
                        style: AppTypography.captionSecondary)
                    : Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              _threadTitle(d.latestThread!),
                              style: AppTypography.body,
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
              const SizedBox(height: AppSpacing.listGap),
              EntranceCard(
                icon: Icons.sticky_note_2_outlined,
                title: '연결노트',
                child: d.latestMentorNote?.body?.trim().isNotEmpty == true
                    ? Text(
                        d.latestMentorNote!.body!.trim(),
                        style: AppTypography.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const Text('멘토가 남긴 노트가 아직 없어요.',
                        style: AppTypography.captionSecondary),
                onTap: () => _openNotes(),
              ),
            ],
          );
        },
      ),
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
