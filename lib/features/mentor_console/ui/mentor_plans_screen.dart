import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_input_field.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/app_badge.dart';
import '../../../design/widgets/glass_card.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/app_blocks.dart';
import '../../mentors/format/mentor_price_format.dart';
import '../data/mentor_console_models.dart';
import '../data/mentor_console_repository.dart';

/// 요금제 설정(A-4a #2) + 개별질문 답변 단가(#3) — `/profile/plans`.
///
/// design-v3 §4-3: 슬라이더가 아니라 **직접 입력 + 범위 안내**. 범위를 벗어나면
/// 그 자리에서 문장으로 알리고 저장 버튼을 비활성으로 둔다. 최종 판정은 서버
/// (F8 `PLAN_PRICE_OUT_OF_BAND`)가 정본이다. 3등급은 한 RPC 로 원자 저장되고,
/// 단가는 별도 RPC(`set_individual_question_price`)라 비어 있으면 건드리지 않는다.
class MentorPlansScreen extends StatefulWidget {
  const MentorPlansScreen({super.key, this.portOverride});

  final MentorConsolePort? portOverride;

  @override
  State<MentorPlansScreen> createState() => _MentorPlansScreenState();
}

class _PlansLoad {
  const _PlansLoad({required this.prices, required this.iqPriceWon});
  final MentorPlanPrices prices;
  final int? iqPriceWon;
}

class _MentorPlansScreenState extends State<MentorPlansScreen> {
  late final MentorConsolePort _port;
  late Future<_PlansLoad> _future;

  final Map<MentorPlanTier, TextEditingController> _tierInputs =
      <MentorPlanTier, TextEditingController>{
    for (final MentorPlanTier t in MentorPlanTier.values)
      t: TextEditingController(),
  };
  final TextEditingController _iqInput = TextEditingController();

  bool _seeded = false;
  bool _saving = false;
  String? _saveError;
  int? _loadedIqPrice;

  @override
  void initState() {
    super.initState();
    _port = widget.portOverride ?? AppScope.of(context).mentorConsole;
    _future = _load();
    for (final TextEditingController c in _tierInputs.values) {
      c.addListener(_onChanged);
    }
    _iqInput.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final TextEditingController c in _tierInputs.values) {
      c.dispose();
    }
    _iqInput.dispose();
    super.dispose();
  }

  Future<_PlansLoad> _load() async {
    final List<dynamic> r = await Future.wait(<Future<dynamic>>[
      _port.loadPlanPrices(),
      _port.loadIndividualQuestionPriceWon(),
    ]);
    final _PlansLoad data = _PlansLoad(
      prices: r[0] as MentorPlanPrices,
      iqPriceWon: r[1] as int?,
    );
    // 입력값 시드는 build 밖(로드 완료 시점)에서 1회 — 컨트롤러 리스너가
    // build 도중 setState 를 부르지 않게 한다.
    if (mounted) _seed(data);
    return data;
  }

  void _retry() {
    _seeded = false;
    setState(() {
      _future = _load();
    });
  }

  void _seed(_PlansLoad data) {
    if (_seeded) return;
    _seeded = true;
    for (final MentorPlanTier t in MentorPlanTier.values) {
      final int? won = data.prices.won(t);
      _tierInputs[t]!.text = won?.toString() ?? '';
    }
    _iqInput.text = data.iqPriceWon?.toString() ?? '';
    _loadedIqPrice = data.iqPriceWon;
  }

  int? _wonOf(TextEditingController c) {
    final String digits = c.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  /// 등급별 오류 문구(null = 정상). 빈 값도 오류(F8 은 3등급 전부 필요).
  String? _tierError(MentorPlanTier tier) {
    final int? won = _wonOf(_tierInputs[tier]!);
    final PlanPriceBand band = PlanPriceBand.of(tier);
    if (won == null) return '금액을 입력해 주세요';
    if (!band.contains(won)) {
      return '${formatWon(band.minWon)} ~ ${formatWon(band.maxWon)} 사이로 적어 주세요';
    }
    return null;
  }

  String? get _iqError {
    if (_iqInput.text.trim().isEmpty) return null; // 비우면 변경 없음.
    final int? won = _wonOf(_iqInput);
    if (won == null || won <= 0) return '1원 이상 숫자로 입력해 주세요';
    return null;
  }

  bool get _allTiersValid =>
      MentorPlanTier.values.every((MentorPlanTier t) => _tierError(t) == null);

  bool get _canSubmit => !_saving && _allTiersValid && _iqError == null;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _port.setPlanPrices(
        limitedWon: _wonOf(_tierInputs[MentorPlanTier.limited]!)!,
        standardWon: _wonOf(_tierInputs[MentorPlanTier.standard]!)!,
        premiumWon: _wonOf(_tierInputs[MentorPlanTier.premium]!)!,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = friendlyError(e);
      });
      return;
    }
    final int? iq = _wonOf(_iqInput);
    if (iq != null && iq > 0 && iq != _loadedIqPrice) {
      try {
        await _port.setIndividualQuestionPriceWon(iq);
        _loadedIqPrice = iq;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _saveError = '요금제는 저장됐지만 개별질문 단가는 저장하지 못했어요. ${friendlyError(e)}';
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('요금제를 저장했어요.')),
    );
    Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: '요금제',
      body: FutureBuilder<_PlansLoad>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<_PlansLoad> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppLoadingView(cards: 3);
          }
          if (snap.hasError || snap.data == null) {
            return AppErrorView(
              title: '요금제를 불러오지 못했어요',
              message: friendlyError(snap.error ?? ''),
              onRetry: _retry,
            );
          }
          return _form(context);
        },
      ),
    );
  }

  Widget _form(BuildContext context) {
    return ListView(
      padding: AppPage.contentPadding(context),
      children: <Widget>[
        Text(
          '요금제마다 정할 수 있는 범위가 달라요',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.base),
        for (final MentorPlanTier tier in MentorPlanTier.values) ...<Widget>[
          _PriceCard(
            title: '${mentorPlanTierLabel(tier)} · ${mentorPlanTierQuotaLabel(tier)}',
            recommended: tier == MentorPlanTier.standard,
            controller: _tierInputs[tier]!,
            enabled: !_saving,
            help: '${formatWon(PlanPriceBand.of(tier).minWon)} ~ '
                '${formatWon(PlanPriceBand.of(tier).maxWon)} 사이',
            error: _tierInputs[tier]!.text.isEmpty ? null : _tierError(tier),
          ),
          const SizedBox(height: 12),
        ],
        _PriceCard(
          title: '지정 개별질문 답변 단가',
          controller: _iqInput,
          enabled: !_saving,
          help: '학생이 나를 지정해 1건 질문할 때의 금액이에요. 비워 두면 바꾸지 않아요.',
          error: _iqError,
        ),
        if (_saveError != null) ...<Widget>[
          const SizedBox(height: 12),
          AppCallout(tone: AppCalloutTone.danger, text: _saveError!),
        ],
        const SizedBox(height: AppSpacing.section),
        AppPrimaryButton(
          label: _saving ? '저장 중…' : '저장하기',
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: 8),
        Text(
          '세 요금제는 한 번에 저장돼요. 범위를 벗어난 값은 저장되지 않아요.',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// 요금 한 칸 — 제목(+추천 배지) · 숫자 입력 · 원 · 범위/오류 문장.
class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.title,
    required this.controller,
    required this.enabled,
    required this.help,
    this.error,
    this.recommended = false,
  });

  final String title;
  final TextEditingController controller;
  final bool enabled;
  final String help;
  final String? error;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title, style: AppTypography.section)),
              if (recommended) const AppBadge(label: '추천'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: AppInputField(
                  controller: controller,
                  hintText: '0',
                  keyboardType: TextInputType.number,
                  enabled: enabled,
                ),
              ),
              const SizedBox(width: 10),
              const Text('원', style: AppTypography.section),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            error ?? help,
            style: AppTypography.caption.copyWith(
              color: error != null ? AppColors.danger : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
