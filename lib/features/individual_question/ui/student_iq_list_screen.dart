import 'package:flutter/material.dart';

import '../../../app/app_navigation.dart';
import '../../../app/app_route_paths.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/typography_tokens.dart';
import '../../../design/widgets/chip_scroll.dart';
import '../../../design/widgets/empty_state.dart';
import '../../../design/widgets/primary_button.dart';
import '../../../core/web_bridge/web_bridge.dart';
import '../../../core/web_bridge/web_bridge_actions.dart';
import '../data/individual_question_repository.dart';
import '../data/models/individual_question_models.dart';
import '../iq_flags.dart';
import 'iq_detail_screen.dart';
import 'widgets/iq_widgets.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/widgets/screen_visibility.dart';

/// 학생 — 내 개별질문 목록. 신규 등록은 경계 확정(2026-08-05)에 따라 웹에서만
/// 한다 — 여기 CTA 는 웹 등록 페이지를 연다. 지정형 등록은 멘토 상세에서 같은
/// 방식으로 진입한다. 조회·상세는 앱에 그대로 남는다.
class StudentIqListScreen extends StatefulWidget {
  const StudentIqListScreen({
    super.key,
    this.loaderOverride,
    this.embedded = false,
    this.webBridgeOverride,
    this.createCtaOverride,
  });

  /// 테스트용 데이터 주입. null 이면 실제 레포 사용.
  final Future<List<IndividualQuestion>> Function()? loaderOverride;

  /// true: 하단 탭(HomeShell)에 임베드 — 자체 Scaffold/AppBar 없이 본문만.
  /// false(기본): 단독 push 화면 — 기존과 동일하게 AppBar 포함.
  final bool embedded;

  /// 테스트용 웹 브릿지 주입(loaderOverride 패턴) — 실사용은 null.
  final WebBridge? webBridgeOverride;

  /// 테스트용 신규 등록 CTA 노출 강제 — 실사용은 null(플래그 기준 기존 판정).
  final bool? createCtaOverride;

  @override
  State<StudentIqListScreen> createState() => _StudentIqListScreenState();
}

class _StudentIqListScreenState extends State<StudentIqListScreen>
    with WidgetsBindingObserver, ResumeVisibilityGate {

  final IndividualQuestionRepository _repo =
      const IndividualQuestionRepository();
  late Future<List<IndividualQuestion>> _future;

  /// 질문 유형 필터(전체/지정/공개·확정/공개·대기). 상태 표기와 독립.
  IqTypeFilter _filter = IqTypeFilter.all;

  @override
  void initState() {
    super.initState();
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
    setState(() => _future = _load());
  }

  /// 신규 등록 CTA 노출 판정 — 기존 플래그 의미 유지(테스트 override 만 추가).
  bool get _createCtaVisible =>
      widget.createCtaOverride ?? kIndividualQuestionCreateEnabled;

  /// 경계 확정(2026-08-05): 신규 등록은 웹 전용 — 네이티브 등록 화면을 열지 않는다.
  /// 웹에서 등록 후 앱으로 돌아오면 당겨서 새로고침(_refresh)이 목록 최신화 경로다.
  Future<void> _openCreate() =>
      openIqCreateWeb(context, bridge: widget.webBridgeOverride);

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
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH, 12, AppSpacing.screenH, 24),
            children: <Widget>[
              if (_createCtaVisible) ...<Widget>[
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
