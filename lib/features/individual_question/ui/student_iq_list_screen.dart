import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_route_paths.dart';
import '../../../app/app_scope.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_blocks.dart';
import '../../../design/widgets/app_empty_state.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/chip_scroll.dart';
import '../data/individual_question_repository.dart';
import '../data/models/individual_question_models.dart';
import '../iq_flags.dart';
import 'iq_create_screen.dart';
import 'iq_detail_screen.dart';
import 'widgets/iq_widgets.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/widgets/screen_visibility.dart';

/// 학생 — 내 개별질문 목록. 신규 등록은 A-4a 개방(2026-09-05)으로 네이티브
/// 등록 화면(`/iq/new`)을 연다. 지정형 등록은 멘토 상세에서 같은 방식으로
/// 진입한다. 등록 성공 시 목록을 새로 읽고 새 질문 상세로 이어간다.
class StudentIqListScreen extends StatefulWidget {
  const StudentIqListScreen({
    super.key,
    this.loaderOverride,
    this.repositoryOverride,
    this.embedded = false,
    this.createCtaOverride,
    this.createScreenOverride,
  });

  /// 테스트용 데이터 주입. null 이면 실제 레포 사용.
  final Future<List<IndividualQuestion>> Function()? loaderOverride;

  /// 테스트용 레포 주입. null 이면 AppScope 의 운영 의존성을 사용한다.
  final IndividualQuestionRepository? repositoryOverride;

  /// true: 하단 탭(HomeShell)에 임베드 — 자체 Scaffold/AppBar 없이 본문만.
  /// false(기본): 단독 push 화면 — 기존과 동일하게 AppBar 포함.
  final bool embedded;

  /// 테스트용 신규 등록 CTA 노출 강제 — 실사용은 null(플래그 기준 기존 판정).
  final bool? createCtaOverride;

  /// 테스트용 등록 화면 빌더(폴백 push 에서 사용) — 실사용은 null(기본 화면).
  final Widget Function(BuildContext context, String? mentorId)?
      createScreenOverride;

  @override
  State<StudentIqListScreen> createState() => _StudentIqListScreenState();
}

class _StudentIqListScreenState extends State<StudentIqListScreen>
    with WidgetsBindingObserver, ResumeVisibilityGate {
  late final IndividualQuestionRepository _repo;
  late Future<List<IndividualQuestion>> _future;

  /// 질문 유형 필터(전체/지정/공개·확정/공개·대기). 상태 표기와 독립.
  IqTypeFilter _filter = IqTypeFilter.all;

  @override
  void initState() {
    super.initState();
    _repo =
        widget.repositoryOverride ?? AppScope.of(context).individualQuestions;
    _future = _load();
    // N34: 등록이 웹 전용이라 웹에서 등록 후 앱 복귀 시 목록이 낡은 채였다 —
    // 질문방 탭과 동일하게 resume 시 재조회한다(PTR 의존 제거).
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

  Future<List<IndividualQuestion>> _load() =>
      (widget.loaderOverride ?? _repo.listForStudent)();

  // ★ 스테일 응답 방어: 새 Future 로 '교체'만 한다 — FutureBuilder 는 최신
  //   Future 의 결과만 반영하므로 이전 로드가 늦게 끝나도 목록을 덮지 않는다.
  void _refresh() {
    if (!mounted) return; // 화면 복귀·당겨서 새로고침 등 await 뒤 호출 대비(P3-4).
    setState(() {
      _future = _load();
    });
  }

  /// 신규 등록 CTA 노출 판정 — 기존 플래그 의미 유지(테스트 override 만 추가).
  bool get _createCtaVisible =>
      widget.createCtaOverride ?? kIndividualQuestionCreateEnabled;

  /// A-4a 개방: 네이티브 등록 화면(`/iq/new`)을 열고, 생성된 질문이 돌아오면
  /// 목록을 새로 읽은 뒤 그 질문의 상세로 이어간다.
  Future<void> _openCreate() async {
    final Object? result = await AppNavigation.push<Object>(
      context,
      AppRoutePaths.newIndividualQuestion,
      fallbackBuilder: (BuildContext ctx) =>
          widget.createScreenOverride?.call(ctx, null) ??
          const IqCreateScreen(),
    );
    if (!mounted || result == null) return;
    _refresh();
    if (result is IndividualQuestion) await _openDetail(result);
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
    return FutureBuilder<List<IndividualQuestion>>(
      future: _future,
      builder:
          (BuildContext context, AsyncSnapshot<List<IndividualQuestion>> snap) {
        if (snap.connectionState != ConnectionState.done) {
          // 스피너 유지(테마 역할색) — 작은 뷰포트 상태 테스트가 이 위젯을 기준으로 본다.
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return AppErrorView(
            title: '개별질문을 불러오지 못했어요',
            message: friendlyError(snap.error!),
            onRetry: _refresh,
          );
        }
        final List<IndividualQuestion> items =
            snap.data ?? const <IndividualQuestion>[];
        if (items.isEmpty) {
          return AppEmptyState(
            icon: Icons.help_outline,
            title: '아직 개별질문이 없어요',
            description: '구독 없이 1건씩 캐시로 질문할 수 있어요.',
            actionLabel: _createCtaVisible ? '새 개별질문' : null,
            onAction: _createCtaVisible ? _openCreate : null,
          );
        }
        final List<IndividualQuestion> filtered = items
            .where((IndividualQuestion q) => iqMatchesTypeFilter(q, _filter))
            .toList(growable: false);
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            clipBehavior: Clip.none,
            padding: AppPage.contentPadding(context),
            children: <Widget>[
              if (_createCtaVisible) ...<Widget>[
                AppPrimaryButton(
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
                    style: AppTypography.captionSecondary,
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
