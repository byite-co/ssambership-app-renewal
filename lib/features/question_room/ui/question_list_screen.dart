import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_route_paths.dart';
import '../../../app/app_scope.dart';
import '../../../core/commerce/commerce_policy.dart';
import '../../../core/entitlement/subscription_summary.dart';
import '../../../core/entitlement/weekly_question_usage.dart';
import '../../../design/role_theme.dart' show RoleTheme;
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_blocks.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/app_secondary_button.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/labels/subscription_copy.dart';
import '../../../shared/widgets/commerce_notice_card.dart';
import '../../../app/routes/individual_question_routes.dart';
import '../../mentors/format/mentor_price_format.dart';
import '../data/models/question_thread.dart';
import '../data/models/room.dart';
import '../data/question_room_read_repository.dart';
import '../data/question_room_write_repository.dart';
import 'chat_screen.dart';
import 'connection_notes_screen.dart';
import 'new_question_screen.dart';
import 'widgets/thread_card.dart';

/// 질문 영역(3뎁스, 학생 전용 화면). 스레드 카드 목록(최신순) + 새 질문 + 연결노트.
/// 멘토는 mentor_question_list_screen 을 쓴다.
class QuestionListScreen extends StatefulWidget {
  const QuestionListScreen({
    super.key,
    required this.room,
    required this.mentorName,
    this.sub,
    this.readRepository,
    this.writeRepository,
  });

  final Room room;
  final String mentorName;
  final SubscriptionSummary? sub;

  /// 테스트 주입 지점. null 이면 AppScope의 운영 레포를 사용.
  final QuestionRoomReadRepository? readRepository;
  final QuestionRoomWriteRepository? writeRepository;

  @override
  State<QuestionListScreen> createState() => _QuestionListScreenState();
}

class _QuestionListScreenState extends State<QuestionListScreen> {
  late final QuestionRoomReadRepository _read;
  late final QuestionRoomWriteRepository _write;

  late Future<List<QuestionThread>> _future;
  bool _busy = false;

  /// A2: 이번 주 질문 사용량(잔여 표시용). null = 미조회/실패 → 표시 생략.
  WeeklyQuestionUsage? _usage;

  @override
  void initState() {
    super.initState();
    _read = widget.readRepository ?? AppScope.of(context).questionRoomRead;
    _write = widget.writeRepository ?? AppScope.of(context).questionRoomWrite;
    _future = _read.threads(widget.room.id);
    _loadUsage();
  }

  void _refresh() {
    if (!mounted) return; // §4: dispose 후 setState 금지.
    // ★ 블록 바디로: setState(() => _future = future)는 클로저가 Future를 반환해
    //   'setState callback returned a Future' 예외로 리빌드가 취소된다(목록 미갱신).
    setState(() {
      _future = _read.threads(widget.room.id);
    });
    _loadUsage();
  }

  /// 주간 사용량 조회(읽기전용). 실패해도 화면 흐름은 막지 않는다.
  Future<void> _loadUsage() async {
    final WeeklyQuestionUsage? u =
        await _read.weeklyUsage(mentorId: widget.room.mentorId);
    if (mounted) setState(() => _usage = u);
  }

  /// N29: '질문하기' 게이트 정본은 서버 get_weekly_question_usage 의 can_ask
  /// (활성 구독 부재 시 limit=0 → false — 구독+주간 잔여를 모두 포함하는 완전
  /// 판정, staging 함수 정의 실측 2026-08-05). 이 화면은 진입·답변 확인·복귀
  /// 마다 usage 를 재조회하므로 게이트가 살아 움직인다. 조회 실패(null)일 때만
  /// push 시점 구독 스냅샷으로 폴백(fail-closed: 둘 다 없으면 false).
  bool get _canAsk => _usage?.canAsk ?? (widget.sub?.canAsk ?? false);

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: '질문 / 답변',
      // 연결노트는 상단 액션으로 둔다 — 하단 '질문하기' 바와 겹치지 않도록(플로팅 제거).
      actions: <Widget>[
        TextButton.icon(
          onPressed: _openNotes,
          icon: const Icon(Icons.sticky_note_2_outlined, size: 20),
          label: const Text('연결노트'),
        ),
        const SizedBox(width: 4),
      ],
      body: FutureBuilder<List<QuestionThread>>(
        future: _future,
        builder:
            (BuildContext context, AsyncSnapshot<List<QuestionThread>> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppLoadingView();
          }
          if (snap.hasError) {
            return AppErrorView(
              title: '질문을 불러오지 못했어요',
              message: friendlyError(snap.error!),
              onRetry: _refresh,
            );
          }
          final List<QuestionThread> threads = snap.data ?? <QuestionThread>[];
          if (threads.isEmpty) {
            return const _EmptyQuestions();
          }
          return ListView.separated(
            clipBehavior: Clip.none,
            padding: AppPage.contentPadding(context, bottom: 12),
            itemCount: threads.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.listGap),
            itemBuilder: (BuildContext context, int i) => ThreadCard(
              thread: threads[i],
              onOpen: () => _openChat(threads[i]),
              bottomAction: _threadActions(threads[i]),
            ),
          );
        },
      ),
      bottom: _askBar(),
    );
  }

  /// 하단 고정 바 — 질문 가능이면 잔여 문장 + 주요 버튼 하나, 이번 주를 다 썼으면
  /// 그 자리에서 두 갈래(design-v3 §3-4: 개별질문으로 지금 물어보기 / 웹 안내).
  Widget _askBar() {
    final String? remaining = SubscriptionCopy.quotaSentence(_usage);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_canAsk) ...<Widget>[
          if (remaining != null) ...<Widget>[
            Text(remaining,
                style: AppTypography.captionSecondary,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.s8),
          ],
          AppPrimaryButton(
            label: '+ 새로운 질문하기',
            onPressed: _busy ? null : _openNewQuestion,
          ),
          // N28: 딥링크 진입은 구독 스냅샷(sub) 없이 열린다 — 서버 사용량이
          // limit>0 이면 구독 자격이 있는 것(정본 판정)이므로 소진 안내로
          // 분기한다(구독 중 학생에게 구독 안내 카드를 띄우는 모순 제거).
        ] else if (widget.sub?.isActive == true ||
            (_usage != null && _usage!.limit > 0)) ...<Widget>[
          // 구독 중인데 이번 주 소진 — 막지 않고 두 갈래(§3-4). 충전·상위 요금제
          // 유도는 두지 않는다(커머스 제로) — 웹 안내 한 줄만 담백하게.
          _exhaustedBlock(),
        ] else ...<Widget>[
          // 커머스 제로: 구매 유도(웹에서 구독) 버튼 제거 → 비상호작용 안내.
          const CommerceNoticeCard(text: kSubscribeNoticeText),
        ],
        // 연결노트는 상단 AppBar 액션(우상단 아이콘) 하나로 통일 — 하단 중복 버튼 제거.
      ],
    );
  }

  /// §3-4 '이번 주 질문을 다 썼을 때' — 주요 행동은 하나(개별질문), 나머지는 물러난다.
  Widget _exhaustedBlock() {
    final String? tier = _usage?.planTier?.trim().isNotEmpty == true
        ? _usage!.planTier
        : widget.sub?.planTier;
    final String head = tier == null || tier.trim().isEmpty
        ? widget.mentorName
        : '${widget.mentorName} · ${planTierLabel(tier)}';
    final String? refill = SubscriptionCopy.refillSentence(_usage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(head, style: AppTypography.meta, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.s4),
        const Text(
          '이번 주 질문을 다 썼어요',
          style: AppTypography.section,
          textAlign: TextAlign.center,
        ),
        if (refill != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s4),
          Text(refill,
              style: AppTypography.captionSecondary,
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: AppSpacing.s12),
        AppPrimaryButton(
          label: '개별질문으로 지금 물어보기',
          onPressed: _openIndividualQuestion,
        ),
        const SizedBox(height: AppSpacing.s8),
        const Text(
          kSubscriptionManageNoticeText,
          style: AppTypography.meta,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// 이 멘토에게 개별질문(캐시) — 기존 네이티브 작성 화면(C8)으로 간다.
  Future<void> _openIndividualQuestion() async {
    await AppNavigation.push<void>(
      context,
      AppRoutePaths.newIndividualQuestionFor(
        widget.room.mentorId,
        mentorName: widget.mentorName,
      ),
      fallbackBuilder: (_) => buildIqCreateFallback(
        mentorId: widget.room.mentorId,
        mentorName: widget.mentorName,
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _openNewQuestion() async {
    final bool? created = await AppNavigation.push<bool>(
      context,
      AppRoutePaths.newRoomThread(widget.room.id),
      fallbackBuilder: (_) => NewQuestionScreen(
        room: widget.room,
        readRepository: _read,
        writeRepository: _write,
      ),
    );
    if (created == true && mounted) _refresh();
  }

  Future<void> _openChat(QuestionThread t) async {
    await AppNavigation.push<void>(
      context,
      AppRoutePaths.roomThread(widget.room.id, t.id),
      fallbackBuilder: (_) => ChatScreen(
        thread: t,
        mentorName: widget.mentorName,
        room: widget.room, // 신고·차단 상대 도출의 정본(참여자 데이터).
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
  }

  Future<void> _confirm(QuestionThread t) async {
    setState(() => _busy = true);
    try {
      await _write.confirmThread(t.id);
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('확인 처리에 실패했어요. ${friendlyError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 카드 하단 액션(학생 전용): 답변 확인 버튼 하나.
  Widget? _threadActions(QuestionThread t) {
    if (t.status != ThreadStatus.answered) return null;
    return AppSecondaryButton(
      label: '답변 확인 완료',
      onPressed: () => _confirm(t),
    );
  }
}

/// 질문 0개 빈 상태 — 웹 기준 3단계 안내.
/// ★ 질문 CTA 버튼은 두지 않는다 — 하단 고정 바(_askBar)의 '+ 새로운 질문하기' 하나로 통일(중복 제거).
class _EmptyQuestions extends StatelessWidget {
  const _EmptyQuestions();

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    return ListView(
      clipBehavior: Clip.none,
      padding: AppPage.contentPadding(context, top: 40),
      children: <Widget>[
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: roleTheme.tint,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.forum_rounded, size: 36, color: roleTheme.color),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        const Text('이 멘토에게 첫 질문을 남겨보세요',
            style: AppTypography.section, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.s20),
        const _Step(n: '1', text: '과목·단원 고르기 (선택)'),
        const _Step(n: '2', text: '궁금한 점 질문 (사진·파일 첨부 가능)'),
        const _Step(n: '3', text: '답변 확인'),
        const SizedBox(height: AppSpacing.s16),
        const Text('연결노트로 기록이 쌓여요',
            style: AppTypography.captionSecondary, textAlign: TextAlign.center),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final String n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _StepNumber(label: n),
          const SizedBox(width: 10),
          Flexible(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }
}

/// 단계 번호 동그라미 — 역할 틴트 + 역할색 숫자.
class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: roleTheme.tint,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: roleTheme.color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
