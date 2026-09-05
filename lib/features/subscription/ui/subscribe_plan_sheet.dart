import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../design/role_theme.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_badge.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/glass_bars.dart';
import '../../../design/widgets/glass_inner.dart';
import '../../../shared/constants/plan_constants.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/ids/uuid_v4.dart';
import '../../mentor_console/data/api_web_v1_envelope.dart';
import '../../mentors/data/mentor_models.dart';
import '../../mentors/format/mentor_price_format.dart';
import '../data/subscription_commerce_models.dart';
import '../data/subscription_commerce_repository.dart';

/// 요금제 선택 시트의 결과.
sealed class SubscribeSheetOutcome {
  const SubscribeSheetOutcome();
}

/// 결제 성공 — 반환된 방으로 이동한다.
class SubscribeSheetSuccess extends SubscribeSheetOutcome {
  const SubscribeSheetSuccess(this.result);
  final SubscribeSuccess result;
}

/// 서버가 '이미 구독 중' 으로 거부 — 호출부가 구독 여부를 재조회한다.
class SubscribeSheetAlreadySubscribed extends SubscribeSheetOutcome {
  const SubscribeSheetAlreadySubscribed();
}

/// 요금제 선택 → 캐시 결제 시트(design-v3 §5-3 · A-4b §2-2).
///
/// - 가격은 그 멘토의 실제 `mentor_plans` 행(활성 요금제만).
/// - 멱등 키는 시트가 열릴 때·요금제를 바꿀 때 하나 만들고 **같은 요금제 재시도에는
///   같은 키**를 보낸다(서버가 첫 결과를 재생 — 이중 차감 0).
/// - 요청 중 버튼 잠금(이중 탭 방지) · 잔액 부족이면 비활성.
/// - 오류는 문구 사전으로만 표시하고 **충전 유도는 없다**.
class SubscribePlanSheet extends StatefulWidget {
  const SubscribePlanSheet({
    super.key,
    required this.mentor,
    this.port,
    this.idempotencyKeyFactory,
  });

  final MentorListItem mentor;

  /// 테스트 주입(기본: [AppScope] 의 subscriptionCommerce).
  final SubscriptionCommercePort? port;

  /// 테스트 주입(기본: uuid v4).
  final String Function()? idempotencyKeyFactory;

  static Future<SubscribeSheetOutcome?> show(
    BuildContext context, {
    required MentorListItem mentor,
    SubscriptionCommercePort? port,
    String Function()? idempotencyKeyFactory,
  }) {
    return GlassBottomSheet.show<SubscribeSheetOutcome>(
      context,
      builder: (BuildContext _) => SubscribePlanSheet(
        mentor: mentor,
        port: port,
        idempotencyKeyFactory: idempotencyKeyFactory,
      ),
    );
  }

  @override
  State<SubscribePlanSheet> createState() => _SubscribePlanSheetState();
}

class _SubscribePlanSheetState extends State<SubscribePlanSheet> {
  late final SubscriptionCommercePort _port;

  static const List<String> _tierOrder = <String>[
    'limited',
    'standard',
    'premium',
  ];

  List<MentorPlan> _plans = const <MentorPlan>[];
  bool _plansLoading = false;
  bool _plansFailed = false;

  int? _balanceCents;
  bool _balanceFailed = false;

  String? _selectedTier;
  late String _idempotencyKey;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _port = widget.port ?? AppScope.of(context).subscriptionCommerce;
    _idempotencyKey = _newKey();
    _plans = _sorted(widget.mentor.plans);
    _selectedTier = _defaultTier(_plans);
    if (_plans.isEmpty) _loadPlans();
    _loadBalance();
  }

  String _newKey() => (widget.idempotencyKeyFactory ?? uuidV4)();

  static List<MentorPlan> _sorted(List<MentorPlan> raw) {
    final List<MentorPlan> out = raw
        .where((MentorPlan p) => p.isActive && _tierOrder.contains(p.planTier))
        .toList();
    out.sort((MentorPlan a, MentorPlan b) =>
        _tierOrder.indexOf(a.planTier) - _tierOrder.indexOf(b.planTier));
    return out;
  }

  static String? _defaultTier(List<MentorPlan> plans) {
    if (plans.isEmpty) return null;
    for (final MentorPlan p in plans) {
      if (p.planTier == 'standard') return p.planTier;
    }
    return plans.first.planTier;
  }

  Future<void> _loadPlans() async {
    setState(() {
      _plansLoading = true;
      _plansFailed = false;
    });
    try {
      final MentorListItem? fresh = await AppScope.of(context)
          .mentorDirectory
          .fetchListItemById(widget.mentor.id);
      if (!mounted) return;
      final List<MentorPlan> plans = _sorted(fresh?.plans ?? const <MentorPlan>[]);
      setState(() {
        _plans = plans;
        _selectedTier = _defaultTier(plans);
        _plansLoading = false;
        _plansFailed = plans.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _plansLoading = false;
        _plansFailed = true;
      });
    }
  }

  Future<void> _loadBalance() async {
    setState(() => _balanceFailed = false);
    try {
      final int cents = await _port.fetchWalletBalanceCents();
      if (!mounted) return;
      setState(() => _balanceCents = cents);
    } catch (_) {
      if (!mounted) return;
      // 잔액 미확인 — 숫자를 날조하지 않고 서버 판정에 맡긴다.
      setState(() => _balanceFailed = true);
    }
  }

  MentorPlan? get _selected {
    for (final MentorPlan p in _plans) {
      if (p.planTier == _selectedTier) return p;
    }
    return null;
  }

  int? get _shortfallCents {
    final MentorPlan? p = _selected;
    final int? bal = _balanceCents;
    if (p == null || bal == null) return null;
    final int diff = p.amountCents - bal;
    return diff > 0 ? diff : 0;
  }

  bool get _canSubmit {
    if (_submitting || _selected == null) return false;
    final int? short = _shortfallCents;
    return short == null || short == 0;
  }

  void _select(String tier) {
    if (_submitting || tier == _selectedTier) return;
    setState(() {
      _selectedTier = tier;
      _idempotencyKey = _newKey(); // 요금제가 바뀌면 새 시도 — 키도 새로.
      _error = null;
    });
  }

  Future<void> _submit() async {
    final MentorPlan? plan = _selected;
    if (plan == null || _submitting) return; // 이중 탭 방지.
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final SubscribeSuccess result = await _port.subscribeWithCash(
        mentorId: widget.mentor.id,
        tier: plan.planTier,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(SubscribeSheetSuccess(result));
    } on ApiEnvelopeFailure catch (e) {
      if (!mounted) return;
      if (e.code == 'ALREADY_SUBSCRIBED') {
        Navigator.of(context).pop(const SubscribeSheetAlreadySubscribed());
        return;
      }
      setState(() {
        _submitting = false;
        _error = e.userMessage;
        if (e.code == 'CASH_INSUFFICIENT') {
          final Object? bal = e.body['balance_cents'];
          if (bal is num) _balanceCents = bal.toInt();
        }
        if (e.code == 'IDEMPOTENCY_KEY_CONFLICT' ||
            e.code == 'IDEMPOTENCY_KEY_INVALID') {
          _idempotencyKey = _newKey();
        }
      });
    } catch (e) {
      if (!mounted) return;
      // 네트워크 등 — 같은 키로 재시도하면 서버가 첫 결과를 재생한다.
      setState(() {
        _submitting = false;
        _error = friendlyError(e);
      });
    }
  }

  static String _quotaLabel(String tier) {
    final PlanTier? t = _planTierOf(tier);
    final int? quota = t == null ? null : planWeeklyQuestionQuota[t];
    return quota == null ? '질문 무제한' : '주 $quota문항';
  }

  static PlanTier? _planTierOf(String tier) {
    for (final PlanTier t in PlanTier.values) {
      if (t.name == tier) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final MentorPlan? selected = _selected;
    final int? balance = _balanceCents;
    final int? shortfall = _shortfallCents;
    final int? remaining =
        (selected == null || balance == null) ? null : balance - selected.amountCents;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 6),
        const Text('요금제를 골라주세요', style: AppTypography.section),
        const SizedBox(height: 4),
        Text('${widget.mentor.displayName} 멘토 · 월 구독',
            style: AppTypography.captionSecondary),
        const SizedBox(height: AppSpacing.s16),
        if (_plansLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_plansFailed || _plans.isEmpty)
          _PlansUnavailable(onRetry: _loadPlans)
        else
          for (int i = 0; i < _plans.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 8),
            _PlanRow(
              plan: _plans[i],
              quotaLabel: _quotaLabel(_plans[i].planTier),
              selected: _plans[i].planTier == _selectedTier,
              recommended: _plans[i].planTier == 'standard',
              onTap: () => _select(_plans[i].planTier),
            ),
          ],
        const SizedBox(height: AppSpacing.s16),
        const _HairLine(),
        const SizedBox(height: AppSpacing.s12),
        _SummaryRow(
          label: '내 캐시',
          value: balance == null
              ? (_balanceFailed ? '확인하지 못했어요' : '확인 중…')
              : formatWon(balance ~/ 100),
          onRetry: _balanceFailed ? _loadBalance : null,
        ),
        const SizedBox(height: 6),
        _SummaryRow(
          label: '결제될 금액',
          value: selected == null ? '-' : formatWon(selected.won),
          strong: true,
        ),
        const SizedBox(height: 6),
        _SummaryRow(
          label: '남는 캐시',
          value: remaining == null ? '-' : formatWon(remaining ~/ 100),
          danger: remaining != null && remaining < 0,
        ),
        const SizedBox(height: AppSpacing.s12),
        const _HairLine(),
        if (shortfall != null && shortfall > 0) ...<Widget>[
          const SizedBox(height: AppSpacing.s12),
          Text(
            '잔액이 ${formatWon(shortfall ~/ 100)} 부족해요',
            key: const ValueKey<String>('subscribe-shortfall'),
            style: AppTypography.caption.copyWith(color: AppColors.danger),
          ),
        ],
        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s12),
          Text(
            _error!,
            key: const ValueKey<String>('subscribe-error'),
            style: AppTypography.caption.copyWith(color: AppColors.danger),
          ),
        ],
        const SizedBox(height: AppSpacing.s16),
        AppPrimaryButton(
          label: _submitting
              ? '결제 중…'
              : selected == null
                  ? '구독하기'
                  : '${formatWon(selected.won)}으로 구독하기',
          icon: _submitting ? null : Icons.bookmark_add_rounded,
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: 8),
        const Text(
          '결제 즉시 질문방이 열리고, 다음 달 같은 날 캐시로 자동 갱신돼요.',
          textAlign: TextAlign.center,
          style: AppTypography.captionSecondary,
        ),
      ],
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.plan,
    required this.quotaLabel,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  final MentorPlan plan;
  final String quotaLabel;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = RoleTheme.of(context).color;
    return Semantics(
      button: true,
      selected: selected,
      label: '${plan.displayLabel} ${formatWon(plan.won)} $quotaLabel',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassInner(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ringColor: selected ? accent : null,
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? accent : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(plan.displayLabel, style: AppTypography.bodyStrong),
                        if (recommended) ...<Widget>[
                          const SizedBox(width: 6),
                          const AppBadge(label: '추천'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(quotaLabel, style: AppTypography.captionSecondary),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(formatWon(plan.won), style: AppTypography.bodyStrong),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.danger = false,
    this.onRetry,
  });

  final String label;
  final String value;
  final bool strong;
  final bool danger;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final TextStyle base = strong ? AppTypography.bodyStrong : AppTypography.body;
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: AppTypography.captionSecondary)),
        if (onRetry != null) ...<Widget>[
          TextButton(onPressed: onRetry, child: const Text('다시 확인')),
          const SizedBox(width: 4),
        ],
        Text(
          value,
          style: danger ? base.copyWith(color: AppColors.danger) : base,
        ),
      ],
    );
  }
}

class _PlansUnavailable extends StatelessWidget {
  const _PlansUnavailable({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassInner(
      child: Column(
        children: <Widget>[
          const Text('요금제 정보를 불러오지 못했어요',
              style: AppTypography.captionSecondary),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _HairLine extends StatelessWidget {
  const _HairLine();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 1, child: ColoredBox(color: AppColors.ring));
}
