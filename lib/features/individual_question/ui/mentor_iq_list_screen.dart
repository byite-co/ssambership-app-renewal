import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_route_paths.dart';
import '../../../app/app_scope.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_blocks.dart';
import '../../../design/widgets/app_empty_state.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/chip_scroll.dart';
import '../data/individual_question_repository.dart';
import '../data/iq_error_mapper.dart';
import '../data/models/individual_question_models.dart';
import 'iq_detail_screen.dart';
import 'widgets/iq_widgets.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/widgets/screen_visibility.dart';

/// 멘토 화면에 함께 담는 데이터(대기 공개 질문 + 내 질문).
class MentorIqListData {
  const MentorIqListData({required this.open, required this.mine});

  final List<OpenIndividualQuestion> open;
  final List<IndividualQuestion> mine;
}

/// 멘토 — 개별질문 목록.
/// '수락 대기'(공개형, 위생 필드만)와 '내 질문'(지정형 + 내가 수락한 것)을 담는다.
class MentorIqListScreen extends StatefulWidget {
  const MentorIqListScreen({
    super.key,
    this.loaderOverride,
    this.onClaim,
    this.repositoryOverride,
    this.embedded = false,
  });

  /// 테스트용 데이터 주입. null 이면 실제 레포 사용.
  final Future<MentorIqListData> Function()? loaderOverride;

  /// true: 하단 탭(HomeShell)에 임베드 — 자체 Scaffold/AppBar 없이 본문만.
  /// false(기본): 단독 push 화면 — 기존과 동일하게 AppBar 포함.
  final bool embedded;

  /// 테스트용 수락 동작 주입. null 이면 실제 RPC.
  final Future<IqEscrowResult> Function(String questionId)? onClaim;

  /// 테스트용 레포 주입. null 이면 AppScope의 개별질문 레포를 사용.
  final IndividualQuestionRepository? repositoryOverride;

  @override
  State<MentorIqListScreen> createState() => _MentorIqListScreenState();
}

class _MentorIqListScreenState extends State<MentorIqListScreen>
    with WidgetsBindingObserver, ResumeVisibilityGate {
  late final IndividualQuestionRepository _repo;
  late Future<MentorIqListData> _future;
  bool _claiming = false;

  /// 질문 유형 필터(전체/지정/공개·확정/공개·대기). 상태 표기와 독립.
  IqTypeFilter _filter = IqTypeFilter.all;

  @override
  void initState() {
    super.initState();
    _repo =
        widget.repositoryOverride ?? AppScope.of(context).individualQuestions;
    _future = _load();
    // N34: 공개 질문 등록이 웹에서 일어나므로 앱 복귀 시 수락 대기 목록이
    // 낡은 채였다 — resume 재조회 추가(질문방 탭과 동일 패턴).
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<MentorIqListData> _load() async {
    if (widget.loaderOverride != null) return widget.loaderOverride!();
    // C22: 두 목록은 독립 — 병렬 조회(종전 순차 await).
    final List<dynamic> loaded = await Future.wait(<Future<dynamic>>[
      _repo.listOpenForMentor(),
      _repo.listForMentor(),
    ]);
    return MentorIqListData(
      open: loaded[0] as List<OpenIndividualQuestion>,
      mine: loaded[1] as List<IndividualQuestion>,
    );
  }

  void _refresh() {
    if (!mounted) return; // §4: dispose 후 setState 금지(호출부 산재 방어 일원화).
    setState(() => _future = _load());
  }

  Future<void> _claim(OpenIndividualQuestion q) async {
    if (_claiming) return;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('질문을 수락할까요?'),
        // 컴플라이언스: 확인문에서 금액 표시 제거(제목만).
        content: Text(
          '수락하면 답변 담당 멘토가 돼요.\n'
          '${q.title.isEmpty ? '(제목 없음)' : q.title}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('수락'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _claiming = true);
    try {
      await (widget.onClaim ?? _repo.claimAsMentor)(q.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('질문을 수락했어요. 답변을 작성해 주세요.')),
      );
      _refresh();
      await AppNavigation.push<bool>(
        context,
        AppRoutePaths.individualQuestion(q.id),
        fallbackBuilder: (_) => IqDetailScreen(questionId: q.id),
      );
      if (mounted) _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(iqActionFailureText(e))));
      _refresh(); // 선착 실패 등 — 목록 최신화.
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Future<void> _openDetail(IndividualQuestion q) async {
    final bool? changed = await AppNavigation.push<bool>(
      context,
      AppRoutePaths.individualQuestion(q.id),
      fallbackBuilder: (_) => IqDetailScreen(questionId: q.id),
    );
    if (changed == true && mounted) _refresh();
  }

  /// 질문 유형 필터 칩(전체/지정/공개·확정/공개·대기). ChipScroll 재사용.
  Widget _typeFilterChips() {
    return ChipScroll(
      labels: <String>[
        for (final IqTypeFilter f in kIqTypeFilters) iqTypeFilterLabel(f),
      ],
      selectedIndex: kIqTypeFilters.indexOf(_filter),
      onSelected: (int i) => setState(() => _filter = kIqTypeFilters[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = _buildBody();
    if (widget.embedded) return body;
    return AppPage(title: '개별질문', body: body);
  }

  Widget _buildBody() {
    return FutureBuilder<MentorIqListData>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<MentorIqListData> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const AppLoadingView();
        }
        if (snap.hasError) {
          return AppErrorView(
            title: '개별질문을 불러오지 못했어요',
            message: friendlyError(snap.error!),
            onRetry: _refresh,
          );
        }
        final MentorIqListData data = snap.data ??
            const MentorIqListData(
              open: <OpenIndividualQuestion>[],
              mine: <IndividualQuestion>[],
            );
        if (data.open.isEmpty && data.mine.isEmpty) {
          return const AppEmptyState(
            icon: Icons.help_outline,
            title: '아직 개별질문이 없어요',
            description: '학생이 지정하거나 공개로 올린 질문이 여기에 보여요.',
          );
        }
        // 유형 필터 적용(새 조회 없음, in-memory).
        // '수락 대기(공개형)' 섹션은 정의상 공개·대기 → 필터가 all/공개·대기일 때만.
        // '내 질문'(지정 + 내가 수락한 공개형)은 유형 필터를 각 행에 적용.
        final List<OpenIndividualQuestion> open =
            iqShowOpenWaitingSection(_filter)
                ? data.open
                : const <OpenIndividualQuestion>[];
        final List<IndividualQuestion> mine = data.mine
            .where((IndividualQuestion q) => iqMatchesTypeFilter(q, _filter))
            .toList(growable: false);
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            clipBehavior: Clip.none,
            padding: AppPage.contentPadding(context),
            children: <Widget>[
              _typeFilterChips(),
              const SizedBox(height: 12),
              if (open.isNotEmpty) ...<Widget>[
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('수락 대기 (공개형)',
                      style: AppTypography.captionSecondary),
                ),
                for (final OpenIndividualQuestion q in open)
                  IqOpenQuestionCard(
                    question: q,
                    onClaim: _claiming ? null : () => _claim(q),
                  ),
                const SizedBox(height: 12),
              ],
              if (mine.isNotEmpty) ...<Widget>[
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('내 질문', style: AppTypography.captionSecondary),
                ),
                for (final IndividualQuestion q in mine)
                  IqQuestionCard(
                    question: q,
                    onTap: () => _openDetail(q),
                  ),
              ],
              if (open.isEmpty && mine.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text(
                    '이 조건의 질문이 없어요.',
                    textAlign: TextAlign.center,
                    style: AppTypography.captionSecondary,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
