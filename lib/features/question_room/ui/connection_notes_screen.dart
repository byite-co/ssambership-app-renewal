import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/typography_tokens.dart';
import '../../../design/widgets/app_badge.dart';
import '../../../design/widgets/app_card.dart';
import '../../../design/widgets/empty_state.dart';
import '../../../design/widgets/primary_button.dart';
import '../../../shared/format/formatters.dart';
import '../../../shared/labels/question_room_labels.dart';
import '../data/models/connection_note.dart';
import '../data/models/room.dart';
import '../data/question_room_read_repository.dart';
import '../data/question_room_write_repository.dart';
import '../../../shared/errors/friendly_error.dart';

/// 연결노트(풀스크린). 멘토/학생 노트를 author_role 로 구분.
/// 본인 노트만 추가/수정한다(쓰기 레포가 본인 author 행만 다룸).
/// ★ 필기(잉크)는 연결노트에서 제거됨 — 필기는 '문제 스캔 위 첨삭'으로
///   질문방·개별질문에 배치한다(docs/SCAN_INK_PLAN.md).
class ConnectionNotesScreen extends StatefulWidget {
  const ConnectionNotesScreen({
    super.key,
    required this.room,
    required this.mentorName,
    this.notesLoader,
    this.onSaveNote,
    this.currentUserId,
  });

  final Room room;
  final String mentorName;

  /// 노트 로더 오버라이드(테스트 주입). null 이면 실제 레포 조회.
  final Future<List<ConnectionNote>> Function()? notesLoader;

  /// 저장 오버라이드(테스트 주입). null 이면 실제 upsertMyNote(본인 author 행만).
  final Future<void> Function(String body)? onSaveNote;

  /// 내 사용자 id 오버라이드(테스트용). null 이면 Supabase 세션에서 얻는다.
  final String? currentUserId;

  @override
  State<ConnectionNotesScreen> createState() => _ConnectionNotesScreenState();
}

class _ConnectionNotesScreenState extends State<ConnectionNotesScreen> {
  // A-2: 레포지토리·사용자 id 는 AppScope 에서(직접 생성·클라이언트 참조 0).
  late final AppDependencies _deps;
  QuestionRoomReadRepository get _read => _deps.questionRoomRead;
  QuestionRoomWriteRepository get _write => _deps.questionRoomWrite;
  final TextEditingController _editor = TextEditingController();

  late Future<List<ConnectionNote>> _future;
  bool _saving = false;
  bool _seeded = false;

  String? get _uid => widget.currentUserId ?? _deps.auth.currentUserId;

  @override
  void initState() {
    super.initState();
    _deps = AppScope.of(context);
    _future = _loadNotes();
  }

  Future<List<ConnectionNote>> _loadNotes() =>
      widget.notesLoader != null ? widget.notesLoader!() : _read.notes(widget.room.id);

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _seeded = false;
    setState(() => _future = _loadNotes());
  }

  Future<void> _save() async {
    final String body = _editor.text.trim();
    if (body.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      if (widget.onSaveNote != null) {
        await widget.onSaveNote!(body);
      } else {
        await _write.upsertMyNote(roomId: widget.room.id, body: body);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노트를 저장했어요.')),
        );
        await _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장에 실패했어요. ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('연결노트')),
      body: FutureBuilder<List<ConnectionNote>>(
        future: _future,
        builder: (BuildContext context,
            AsyncSnapshot<List<ConnectionNote>> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('노트를 불러오지 못했어요.\n${friendlyError(snap.error!)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: ColorTokens.danger)),
              ),
            );
          }
          final List<ConnectionNote> notes = snap.data ?? <ConnectionNote>[];
          final List<ConnectionNote> mine = notes
              .where((ConnectionNote n) => _uid != null && n.authorId == _uid)
              .toList();
          final List<ConnectionNote> others = notes
              .where((ConnectionNote n) => !(_uid != null && n.authorId == _uid))
              .toList()
            ..sort((ConnectionNote a, ConnectionNote b) =>
                a.createdAt.compareTo(b.createdAt)); // 상대 노트 시간순

          // 내 기존 노트 본문으로 에디터 1회 시드.
          if (!_seeded) {
            _editor.text = mine.isNotEmpty ? (mine.first.body ?? '') : '';
            _seeded = true;
          }

          return ListView(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH, vertical: AppSpacing.s16),
            children: <Widget>[
              Text('상대 노트', style: AppType.caption),
              const SizedBox(height: AppSpacing.titleBody),
              if (others.isEmpty)
                // 노트가 하나도 없을 때만 빈 상태(편집기는 아래 유지). 편집 맥락이라
                // '질문하러 가기'(탭 이탈) CTA는 두지 않는다.
                (mine.isEmpty
                    ? const EmptyState(
                        icon: Icons.edit_note_rounded,
                        title: '아직 연결노트가 없어요',
                        message: '질문하고 답변을 확인하면 노트가 쌓여요',
                      )
                    : Text('상대가 남긴 노트가 아직 없어요.', style: AppType.caption))
              else
                for (final ConnectionNote n in others) ...<Widget>[
                  _NoteCard(note: n),
                  const SizedBox(height: AppSpacing.cardGap),
                ],
              const SizedBox(height: AppSpacing.section),
              Text('내 노트', style: AppType.caption),
              const SizedBox(height: AppSpacing.titleBody),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: _editor,
                      style: AppType.body,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: '이 멘토방에 대한 내 메모를 남겨요.',
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PrimaryButton(
                      label: _saving ? '저장 중…' : '내 노트 저장',
                      onPressed: _saving ? null : _save,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});
  final ConnectionNote note;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppBadge(
                label: QuestionRoomLabels.noteAuthorRole(note.authorRole),
                tinted: note.authorRole == NoteAuthorRole.mentor,
              ),
              const Spacer(),
              Text(Formatters.relativeKorean(note.updatedAt),
                  style: AppType.caption),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            note.body?.trim().isNotEmpty == true ? note.body!.trim() : '(내용 없음)',
            style: AppType.body,
          ),
        ],
      ),
    );
  }
}
