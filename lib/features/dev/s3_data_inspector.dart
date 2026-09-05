import 'package:flutter/material.dart';

import '../../data/mappings/subject_labels.dart';
import '../../design/tokens/color_tokens.dart';
import '../../design/typography_tokens.dart';
import '../../design/widgets/app_badge.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/status_pill.dart';
import '../../shared/format/formatters.dart';
import '../../shared/labels/question_room_labels.dart';
import '../question_room/data/models/connection_note.dart';
import '../question_room/data/models/question_message.dart';
import '../question_room/data/models/question_thread.dart';
import '../question_room/data/models/room.dart';
import '../question_room/data/question_room_read_repository.dart';

/// 개발 전용 'S3 데이터 점검' 화면.
/// 로그인 사용자의 방 → 스레드 → 메시지, 그리고 방의 연결노트(역할 구분)를
/// 실데이터로 나열해 데이터 계층/RLS가 동작하는지 눈으로 확인한다.
///
/// ★ dev 전용(출시 빌드 미등록). 디자인은 기존 위젯/토큰만, 색 추가 없음.
///   내부 UUID·테이블명·영문 status 를 그대로 노출하지 않는다(라벨/요약만).
class S3DataInspector extends StatefulWidget {
  const S3DataInspector({
    super.key,
    required this.repository,
  });

  final QuestionRoomReadRepository repository;

  @override
  State<S3DataInspector> createState() => _S3DataInspectorState();
}

class _S3DataInspectorState extends State<S3DataInspector> {
  Room? _room;
  int _roomIndex = 0;
  QuestionThread? _thread;

  @override
  Widget build(BuildContext context) {
    final String title = _thread != null
        ? '점검 · 메시지'
        : _room != null
            ? '점검 · 방 #${_roomIndex + 1}'
            : 'S3 데이터 점검 (개발용)';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _room != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goBack,
              )
            : null,
      ),
      body: _thread != null
          ? _MessagesView(repo: widget.repository, thread: _thread!)
          : _room != null
              ? _RoomDetailView(
                  repo: widget.repository,
                  room: _room!,
                  index: _roomIndex,
                  onOpenThread: (QuestionThread t) =>
                      setState(() => _thread = t),
                )
              : _RoomsView(
                  repo: widget.repository,
                  onOpenRoom: (Room r, int i) => setState(() {
                    _room = r;
                    _roomIndex = i;
                  }),
                ),
    );
  }

  void _goBack() {
    setState(() {
      if (_thread != null) {
        _thread = null;
      } else {
        _room = null;
      }
    });
  }
}

/// 공용: 비동기 로더 + 로딩/에러/빈 처리. 에러는 삼키지 않고 화면에 그대로 보여준다.
class _AsyncList<T> extends StatelessWidget {
  const _AsyncList({
    required this.future,
    required this.emptyTitle,
    required this.builder,
    super.key,
  });

  final Future<List<T>> future;
  final String emptyTitle;
  final Widget Function(BuildContext, List<T>) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<List<T>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorBox(message: '$emptyTitle 불러오기 실패\n${snap.error}');
        }
        final List<T> items = snap.data ?? <T>[];
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.inbox_outlined,
            title: emptyTitle,
            message: '표시할 데이터가 없어요.',
          );
        }
        return builder(context, items);
      },
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
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

/// 1단계: 내 방 목록.
class _RoomsView extends StatelessWidget {
  const _RoomsView({required this.repo, required this.onOpenRoom});

  final QuestionRoomReadRepository repo;
  final void Function(Room, int) onOpenRoom;

  @override
  Widget build(BuildContext context) {
    return _AsyncList<Room>(
      future: repo.myRooms(),
      emptyTitle: '내 방',
      builder: (BuildContext context, List<Room> rooms) {
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rooms.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (BuildContext context, int i) {
            final Room r = rooms[i];
            return AppCard(
              onTap: () => onOpenRoom(r, i),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('방 #${i + 1}', style: AppType.body),
                        const SizedBox(height: 4),
                        Text(
                          '개설 ${Formatters.koreanDate(r.createdAt)}',
                          style: AppType.caption,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: ColorTokens.muted),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 2단계: 선택한 방의 스레드 목록 + 연결노트(역할 구분).
class _RoomDetailView extends StatelessWidget {
  const _RoomDetailView({
    required this.repo,
    required this.room,
    required this.index,
    required this.onOpenThread,
  });

  final QuestionRoomReadRepository repo;
  final Room room;
  final int index;
  final void Function(QuestionThread) onOpenThread;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('질문 스레드', style: AppType.caption),
        const SizedBox(height: 10),
        _ThreadList(repo: repo, roomId: room.id, onOpenThread: onOpenThread),
        const SizedBox(height: 24),
        Text('연결노트', style: AppType.caption),
        const SizedBox(height: 10),
        _NoteList(repo: repo, roomId: room.id),
      ],
    );
  }
}

class _ThreadList extends StatelessWidget {
  const _ThreadList({
    required this.repo,
    required this.roomId,
    required this.onOpenThread,
  });

  final QuestionRoomReadRepository repo;
  final String roomId;
  final void Function(QuestionThread) onOpenThread;

  static StatusTone _tone(ThreadStatus s) {
    switch (s) {
      case ThreadStatus.pending:
        return StatusTone.warning;
      case ThreadStatus.answered:
      case ThreadStatus.open:
        return StatusTone.info;
      case ThreadStatus.confirmed:
        return StatusTone.success;
      case ThreadStatus.closed:
      case ThreadStatus.archived:
      case ThreadStatus.unknown:
        return StatusTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QuestionThread>>(
      future: repo.threads(roomId),
      builder: (BuildContext context,
          AsyncSnapshot<List<QuestionThread>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return _ErrorBox(message: '스레드 불러오기 실패\n${snap.error}');
        }
        final List<QuestionThread> threads = snap.data ?? <QuestionThread>[];
        if (threads.isEmpty) {
          return Text('스레드가 없어요.', style: AppType.caption);
        }
        return Column(
          children: <Widget>[
            for (final QuestionThread t in threads) ...<Widget>[
              AppCard(
                onTap: () => onOpenThread(t),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            t.title?.trim().isNotEmpty == true
                                ? t.title!
                                : '(제목 없음)',
                            style: AppType.body,
                          ),
                        ),
                        StatusPill(
                          label: QuestionRoomLabels.threadStatus(t.status),
                          tone: _tone(t.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        AppBadge(label: subjectLabel(t.subject), tinted: true),
                        AppBadge(
                          label: '숙련: '
                              '${QuestionRoomLabels.masteryStatus(t.masteryStatus)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _NoteList extends StatelessWidget {
  const _NoteList({required this.repo, required this.roomId});

  final QuestionRoomReadRepository repo;
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ConnectionNote>>(
      future: repo.notes(roomId),
      builder: (BuildContext context,
          AsyncSnapshot<List<ConnectionNote>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return _ErrorBox(message: '노트 불러오기 실패\n${snap.error}');
        }
        final List<ConnectionNote> notes = snap.data ?? <ConnectionNote>[];
        if (notes.isEmpty) {
          return Text('연결노트가 없어요.', style: AppType.caption);
        }
        return Column(
          children: <Widget>[
            for (final ConnectionNote n in notes) ...<Widget>[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AppBadge(
                      label: QuestionRoomLabels.noteAuthorRole(n.authorRole),
                      tinted: n.authorRole == NoteAuthorRole.mentor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      n.body?.trim().isNotEmpty == true ? n.body! : '(내용 없음)',
                      style: AppType.body,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

/// 3단계: 스레드의 메시지(대화 순서).
class _MessagesView extends StatelessWidget {
  const _MessagesView({required this.repo, required this.thread});

  final QuestionRoomReadRepository repo;
  final QuestionThread thread;

  @override
  Widget build(BuildContext context) {
    return _AsyncList<QuestionMessage>(
      future: repo.messages(thread.id),
      emptyTitle: '메시지',
      builder: (BuildContext context, List<QuestionMessage> messages) {
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (BuildContext context, int i) {
            final QuestionMessage m = messages[i];
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    Formatters.koreanDate(m.createdAt),
                    style: AppType.caption,
                  ),
                  const SizedBox(height: 6),
                  Text(m.body, style: AppType.body),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
