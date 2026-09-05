import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../design/role_theme.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_empty_state.dart';
import '../../../design/widgets/app_input_field.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/app_badge.dart';
import '../../../design/widgets/glass_card.dart';
import '../../../design/widgets/glass_inner.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/format/formatters.dart';
import '../../../shared/labels/question_room_labels.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/app_blocks.dart';
import '../data/connection_note_errors.dart';
import '../data/mentor_note_format.dart';
import '../data/models/connection_note.dart';
import '../data/models/room.dart';
import '../data/question_room_read_repository.dart';
import '../data/question_room_write_repository.dart';

/// 연결노트(A-5 §2-3·§2-4) — 쌓인다 · 고쳐 쓰지 않는다.
///
/// - 저장은 **INSERT 전용**(수정·삭제 경로 없음). 타임라인은 `created_at` 최신순으로
///   전부 그린다(건수 가정 없음).
/// - 학생: 최신 멘토 노트 요약을 맨 위에("내 멘토가 나를 안다"는 증거) + 내 메모 한 칸.
/// - 멘토: 두 질문(약점 / 다음에 풀 유형)으로 쓰게 유도, 노트가 없으면 작성 예시.
/// - DB `UNIQUE(room, author)` 가 남아 있는 동안 두 번째 노트는 23505 →
///   "이미 남긴 노트가 있어요. 곧 여러 개를 남길 수 있게 돼요"(지시서 2-6).
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

  /// 상대 표시명 — 학생 화면이면 멘토 이름, 멘토 화면이면 학생 이름(호출부 관례).
  final String mentorName;

  /// 노트 로더 오버라이드(테스트 주입). null 이면 실제 레포 조회.
  final Future<List<ConnectionNote>> Function()? notesLoader;

  /// 저장 오버라이드(테스트 주입). null 이면 실제 insertMyNote(본인 author 행 INSERT).
  final Future<void> Function(String body)? onSaveNote;

  /// 내 사용자 id 오버라이드(테스트용). null 이면 세션에서 얻는다.
  final String? currentUserId;

  @override
  State<ConnectionNotesScreen> createState() => _ConnectionNotesScreenState();
}

class _ConnectionNotesScreenState extends State<ConnectionNotesScreen> {
  late final AppDependencies _deps;
  QuestionRoomReadRepository get _read => _deps.questionRoomRead;
  QuestionRoomWriteRepository get _write => _deps.questionRoomWrite;

  // 학생: 한 칸. 멘토: 두 질문.
  final TextEditingController _memo = TextEditingController();
  final TextEditingController _weakness = TextEditingController();
  final TextEditingController _next = TextEditingController();

  late Future<List<ConnectionNote>> _future;
  bool _saving = false;

  String? get _uid => widget.currentUserId ?? _deps.auth.currentUserId;

  /// 멘토 화면인지 — 방의 멘토가 나일 때만. (uid 미상이면 학생 화면.)
  bool get _isMentor => _uid != null && _uid == widget.room.mentorId;

  @override
  void initState() {
    super.initState();
    _deps = AppScope.of(context);
    _future = _loadNotes();
    _memo.addListener(_onEdit);
    _weakness.addListener(_onEdit);
    _next.addListener(_onEdit);
  }

  void _onEdit() => setState(() {});

  Future<List<ConnectionNote>> _loadNotes() => widget.notesLoader != null
      ? widget.notesLoader!()
      : _read.notes(widget.room.id);

  @override
  void dispose() {
    _memo.dispose();
    _weakness.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadNotes();
    });
  }

  String? get _composedBody => _isMentor
      ? composeMentorNote(weakness: _weakness.text, next: _next.text)
      : (_memo.text.trim().isEmpty ? null : _memo.text.trim());

  Future<void> _save() async {
    final String? body = _composedBody;
    if (body == null || _saving) return;
    setState(() => _saving = true);
    try {
      if (widget.onSaveNote != null) {
        await widget.onSaveNote!(body);
      } else {
        await _write.insertMyNote(roomId: widget.room.id, body: body);
      }
      if (!mounted) return;
      _memo.clear();
      _weakness.clear();
      _next.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('노트를 저장했어요.')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      final Object mapped = mapNoteInsertError(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapped is NoteAlreadyExistsError
                ? mapped.userMessage // 지시서 2-6 문구 그대로.
                : '저장에 실패했어요. ${friendlyError(mapped)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: _isMentor ? '연결노트 · ${widget.mentorName}' : '연결노트',
      body: FutureBuilder<List<ConnectionNote>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<List<ConnectionNote>> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppLoadingView(cards: 2);
          }
          if (snap.hasError) {
            return AppErrorView(
              title: '노트를 불러오지 못했어요',
              message: friendlyError(snap.error!),
              onRetry: _reload,
            );
          }
          final List<ConnectionNote> notes =
              List<ConnectionNote>.of(snap.data ?? const <ConnectionNote>[])
                ..sort((ConnectionNote a, ConnectionNote b) =>
                    b.createdAt.compareTo(a.createdAt)); // 최신이 위.
          return _isMentor ? _mentorBody(notes) : _studentBody(notes);
        },
      ),
    );
  }

  // ── 학생(§2-4) ──
  Widget _studentBody(List<ConnectionNote> notes) {
    ConnectionNote? latestMentor;
    for (final ConnectionNote n in notes) {
      if (n.authorRole == NoteAuthorRole.mentor) {
        latestMentor = n;
        break;
      }
    }
    // 요약 카드에 올린 최신 멘토 노트는 타임라인에서 한 번 더 그리지 않는다.
    final List<ConnectionNote> rest = <ConnectionNote>[
      for (final ConnectionNote n in notes)
        if (!identical(n, latestMentor)) n,
    ];
    return ListView(
      padding: AppPage.contentPadding(context),
      children: <Widget>[
        if (latestMentor == null)
          const AppEmptyState(
            icon: Icons.edit_note_rounded,
            title: '아직 노트가 없어요',
            description: '질문을 주고받으면 멘토가 약한 부분을 적어줘요',
          )
        else
          _MentorSummaryCard(note: latestMentor, mentorName: widget.mentorName),
        const SizedBox(height: AppSpacing.section),
        const AppSectionTitle('내가 정리한 것'),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppInputField(
                controller: _memo,
                hintText: '이 멘토방에 대한 내 메모를 남겨요.',
                minLines: 3,
                maxLines: 8,
                enabled: !_saving,
              ),
              const SizedBox(height: 10),
              AppPrimaryButton(
                label: _saving ? '저장 중…' : '내 노트 저장',
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
        if (rest.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.section),
          AppSectionTitle('지난 노트 ${rest.length}개'),
          for (final ConnectionNote n in rest) ...<Widget>[
            _NoteCard(note: n, mine: _uid != null && n.authorId == _uid),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }

  // ── 멘토(§2-3·§2-5) ──
  Widget _mentorBody(List<ConnectionNote> notes) {
    // 시계 의존(DateTime.now) 없이 고정 사실만 — 골든이 날짜에 따라 흔들리지 않는다.
    final String since = Formatters.koreanDate(widget.room.createdAt.toLocal());
    return ListView(
      padding: AppPage.contentPadding(context),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '$since부터 함께 · 노트 ${notes.length}개',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
        ),
        if (notes.isEmpty) const _FirstNoteExampleCard(),
        if (notes.isEmpty) const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('노트 남기기', style: AppTypography.section),
              const SizedBox(height: 4),
              Text(
                '진도가 아니라 약점을 적어요. 지난 노트는 고치지 않아요 — 이력이에요.',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.base),
              AppField(
                label: '오늘 무엇이 약했나요?',
                child: AppInputField(
                  controller: _weakness,
                  hintText: '예: 분모 조건을 확인하지 않고 대입해요',
                  minLines: 1,
                  maxLines: 3,
                  enabled: !_saving,
                ),
              ),
              const SizedBox(height: 12),
              AppField(
                label: '다음에 어떤 유형을 풀면 좋을까요?',
                child: AppInputField(
                  controller: _next,
                  hintText: '예: 좌·우극한이 다른 그래프 문제',
                  minLines: 1,
                  maxLines: 3,
                  enabled: !_saving,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              AppPrimaryButton(
                label: _saving ? '저장 중…' : '노트 저장',
                onPressed: _saving || _composedBody == null ? null : _save,
              ),
            ],
          ),
        ),
        if (notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.section),
          const AppSectionTitle('타임라인'),
          for (final ConnectionNote n in notes) ...<Widget>[
            _NoteCard(note: n, mine: _uid != null && n.authorId == _uid),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}

/// 학생 화면 맨 위 — 최신 멘토 노트 요약("{멘토}가 본 나").
class _MentorSummaryCard extends StatelessWidget {
  const _MentorSummaryCard({required this.note, required this.mentorName});

  final ConnectionNote note;
  final String mentorName;

  @override
  Widget build(BuildContext context) {
    final MentorNoteParts parts = MentorNoteParts.parse(note.body);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('$mentorName 멘토가 본 나', style: AppTypography.section),
          const SizedBox(height: 10),
          if (parts.isStructured) ...<Widget>[
            if (parts.weakness != null)
              _SummaryRow(icon: Icons.lightbulb_outline_rounded, label: '지금 약한 것', text: parts.weakness!),
            if (parts.next != null)
              _SummaryRow(icon: Icons.play_arrow_rounded, label: '다음에 풀어볼 유형', text: parts.next!),
          ] else
            Text(parts.plain ?? '', style: AppTypography.body),
          const SizedBox(height: 6),
          Text(
            '${Formatters.relativeKorean(note.createdAt)} · $mentorName 멘토',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.label, required this.text});

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassInner(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: roleTheme.color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(text, style: AppTypography.body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 멘토 빈 상태(§2-5) — 입력창만 두지 않고 첫 노트에 무엇을 쓰는지 예시로 보여준다.
class _FirstNoteExampleCard extends StatelessWidget {
  const _FirstNoteExampleCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('아직 노트가 없어요', style: AppTypography.section),
          const SizedBox(height: 4),
          Text(
            '답변을 보낸 뒤 한 줄만 남겨도 다음 달 재구독이 달라져요',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          GlassInner(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('이렇게 씁니다', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                const Text('$kMentorNoteWeaknessLabel  조건 확인 없이 공식부터 대입해요', style: AppTypography.body),
                const SizedBox(height: 4),
                const Text('$kMentorNoteNextLabel  정의역이 제한된 유리함수', style: AppTypography.body),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '"극한 3문제 풀었음" 같은 진도는 학생에게 도움이 되지 않아요.',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 타임라인 카드 — 역할 배지 + 날짜 + 본문(규약이면 두 항목).
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.mine});

  final ConnectionNote note;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final MentorNoteParts parts = MentorNoteParts.parse(note.body);
    final String body = note.body?.trim().isNotEmpty == true ? note.body!.trim() : '(내용 없음)';
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppBadge(label: QuestionRoomLabels.noteAuthorRole(note.authorRole)),
              if (mine) ...<Widget>[
                const SizedBox(width: 6),
                Text('나', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
              ],
              const Spacer(),
              Text(
                Formatters.koreanDate(note.createdAt.toLocal()),
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (parts.isStructured) ...<Widget>[
            if (parts.weakness != null) _PartLine(label: kMentorNoteWeaknessLabel, text: parts.weakness!),
            if (parts.next != null) _PartLine(label: kMentorNoteNextLabel, text: parts.next!),
          ] else
            Text(body, style: AppTypography.body),
        ],
      ),
    );
  }
}

class _PartLine extends StatelessWidget {
  const _PartLine({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }
}
