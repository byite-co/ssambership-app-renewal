import 'package:flutter/material.dart';

import '../../../design/spacing_tokens.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/typography_tokens.dart';
import '../../../design/widgets/chip_scroll.dart';
import '../../../design/widgets/empty_state.dart';
import '../../../design/widgets/primary_button.dart';
import '../data/individual_question_repository.dart';
import '../data/models/individual_question_models.dart';
import '../iq_flags.dart';
import 'iq_create_screen.dart';
import 'iq_detail_screen.dart';
import 'widgets/iq_widgets.dart';
import '../../../shared/errors/friendly_error.dart';

/// 학생 — 내 개별질문 목록. 작성은 공개형(전체 멘토 대상);
/// 지정형은 멘토 상세의 '개별질문 하기'에서 진입한다.
class StudentIqListScreen extends StatefulWidget {
  const StudentIqListScreen({
    super.key,
    this.loaderOverride,
    this.embedded = false,
  });

  /// 테스트용 데이터 주입. null 이면 실제 레포 사용.
  final Future<List<IndividualQuestion>> Function()? loaderOverride;

  /// true: 하단 탭(HomeShell)에 임베드 — 자체 Scaffold/AppBar 없이 본문만.
  /// false(기본): 단독 push 화면 — 기존과 동일하게 AppBar 포함.
  final bool embedded;

  @override
  State<StudentIqListScreen> createState() => _StudentIqListScreenState();
}

class _StudentIqListScreenState extends State<StudentIqListScreen> {
  final IndividualQuestionRepository _repo =
      const IndividualQuestionRepository();
  late Future<List<IndividualQuestion>> _future;

  /// 질문 유형 필터(전체/지정/공개·확정/공개·대기). 상태 표기와 독립.
  IqTypeFilter _filter = IqTypeFilter.all;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<IndividualQuestion>> _load() =>
      (widget.loaderOverride ?? _repo.listForStudent)();

  // ★ 스테일 응답 방어: 새 Future 로 '교체'만 한다 — FutureBuilder 는 최신
  //   Future 의 결과만 반영하므로 이전 로드가 늦게 끝나도 목록을 덮지 않는다.
  void _refresh() {
    if (!mounted) return; // 화면 복귀·당겨서 새로고침 등 await 뒤 호출 대비(P3-4).
    setState(() => _future = _load());
  }

  Future<void> _openCreate() async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const IqCreateScreen(),
      ),
    );
    if (created == true && mounted) _refresh();
  }

  Future<void> _openDetail(IndividualQuestion q) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => IqDetailScreen(questionId: q.id),
      ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('개별질문')),
      body: body,
    );
  }

  Widget _buildBody() {
    return FutureBuilder<List<IndividualQuestion>>(
      future: _future,
      builder:
          (BuildContext context, AsyncSnapshot<List<IndividualQuestion>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('개별질문을 불러오지 못했어요.\n${friendlyError(snap.error!)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: ColorTokens.danger)),
            ),
          );
        }
        final List<IndividualQuestion> items =
            snap.data ?? const <IndividualQuestion>[];
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.help_outline,
            title: '아직 개별질문이 없어요',
            message: '구독 없이 1건씩 캐시로 질문할 수 있어요.',
            actionLabel: kIndividualQuestionCreateEnabled ? '새 개별질문' : null,
            onAction: kIndividualQuestionCreateEnabled ? _openCreate : null,
          );
        }
        final List<IndividualQuestion> filtered = items
            .where((IndividualQuestion q) => iqMatchesTypeFilter(q, _filter))
            .toList(growable: false);
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH, 12, AppSpacing.screenH, 24),
            children: <Widget>[
              if (kIndividualQuestionCreateEnabled) ...<Widget>[
                PrimaryButton(
                  label: '새 개별질문 (공개형)',
                  icon: Icons.add,
                  onPressed: _openCreate,
                ),
                const SizedBox(height: 14),
              ],
              _typeFilterChips(),
              const SizedBox(height: 12),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text(
                    '이 조건의 질문이 없어요.',
                    textAlign: TextAlign.center,
                    style: AppType.caption,
                  ),
                )
              else
                for (final IndividualQuestion q in filtered)
                  IqQuestionCard(
                    question: q,
                    onTap: () => _openDetail(q),
                  ),
            ],
          ),
        );
      },
    );
  }
}
