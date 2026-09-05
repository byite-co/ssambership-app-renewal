import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/refresh/data_refresh_bus.dart';
import '../../../design/role_theme.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_badge.dart';
import '../../../design/widgets/app_blocks.dart';
import '../../../design/widgets/app_input_field.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/glass_card.dart';
import '../../../design/widgets/glass_inner.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/format/formatters.dart';
import '../../mentors/format/mentor_price_format.dart';
import '../data/subscription_commerce_models.dart';
import '../data/subscription_commerce_repository.dart';

/// 환불 신청(design-v3 §5-9 · A-4b §2-4) — `/me/subscriptions/:id/refund`.
///
/// 1. `refund_estimate` 로 **예상액과 근거 규칙**을 먼저 보여준다(숫자는 서버 값만).
/// 2. 사유(5자 이상 · 2000자 이하)를 받아 `refund_request_create` → pending.
/// 예상액 0원이어도 신청은 가능하되 경고를 먼저 보인다. 충전 유도 없음.
class RefundRequestScreen extends StatefulWidget {
  const RefundRequestScreen({
    super.key,
    required this.subscriptionId,
    required this.mentorName,
    this.planLabel,
    this.port,
  });

  final String subscriptionId;
  final String mentorName;
  final String? planLabel;

  /// 테스트 주입(기본: [AppScope]).
  final SubscriptionCommercePort? port;

  /// 사유 선택지(웹·목업 §5-9 동일). 마지막은 직접 입력.
  static const List<String> reasonPresets = <String>[
    '답변이 너무 늦어요',
    '답변 내용이 도움이 안 돼요',
    '실수로 결제했어요',
  ];
  static const String reasonOther = '그 밖의 이유';
  static const int reasonMinLength = 5;
  static const int reasonMaxLength = 2000;

  @override
  State<RefundRequestScreen> createState() => _RefundRequestScreenState();
}

class _RefundRequestScreenState extends State<RefundRequestScreen> {
  late final SubscriptionCommercePort _port;
  late Future<RefundEstimate> _future;
  final TextEditingController _other = TextEditingController();

  String? _reason; // 선택된 preset 또는 reasonOther
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _port = widget.port ?? AppScope.of(context).subscriptionCommerce;
    _future = _port.refundEstimate(widget.subscriptionId);
    _other.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _retry() {
    final Future<RefundEstimate> next = _port.refundEstimate(widget.subscriptionId);
    setState(() {
      _future = next;
    });
  }

  String? get _reasonText {
    final String? r = _reason;
    if (r == null) return null;
    if (r != RefundRequestScreen.reasonOther) return r;
    final String t = _other.text.trim();
    return t.isEmpty ? null : t;
  }

  String? get _reasonProblem {
    if (_reason != RefundRequestScreen.reasonOther) return null;
    final String t = _other.text.trim();
    if (t.isEmpty) return null;
    if (t.length < RefundRequestScreen.reasonMinLength) {
      return '사유를 ${RefundRequestScreen.reasonMinLength}자 이상 적어 주세요';
    }
    return null;
  }

  bool get _canSubmit =>
      !_submitting &&
      _reasonText != null &&
      _reasonText!.length >= RefundRequestScreen.reasonMinLength &&
      _reasonText!.length <= RefundRequestScreen.reasonMaxLength;

  Future<void> _submit() async {
    final String? reason = _reasonText;
    if (reason == null || !_canSubmit) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await _port.refundRequestCreate(
        subscriptionId: widget.subscriptionId,
        reason: reason,
      );
      if (!mounted) return;
      DataRefreshBus.bumpSubscription();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('환불을 신청했어요. 관리자 확인 뒤 캐시로 돌려받아요.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = friendlyError(e);
      });
    }
  }

  static String _ruleExplain(RefundEstimate e) {
    switch (e.bracketReason) {
      case 'before_usage':
        return '이용 개시 전 — 전액';
      case 'lt_1_3':
        return '기간의 1/3 전 — 결제액의 2/3';
      case 'lt_1_2':
        return '기간의 1/2 전 — 결제액의 1/2';
      case 'ge_1_2':
        return '기간의 1/2 지남 — 환불액 없음';
      default:
        return '계산 불가 — 관리자가 확인해요';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: '환불 신청',
      subtitle: widget.planLabel == null
          ? widget.mentorName
          : '${widget.mentorName} · ${widget.planLabel}',
      body: FutureBuilder<RefundEstimate>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<RefundEstimate> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppLoadingView(cards: 2);
          }
          final RefundEstimate? est = snap.data;
          if (snap.hasError || est == null) {
            return AppErrorView(
              title: '예상 환불액을 확인하지 못했어요',
              message: friendlyError(snap.error ?? ''),
              onRetry: _retry,
            );
          }
          return _form(context, est);
        },
      ),
      bottom: AppPrimaryButton(
        label: _submitting ? '신청 중…' : '환불 신청하기',
        onPressed: _canSubmit ? _submit : null,
      ),
    );
  }

  Widget _form(BuildContext context, RefundEstimate est) {
    final String? problem = _reasonProblem;
    return ListView(
      clipBehavior: Clip.none,
      padding: AppPage.contentPadding(context, top: AppSpacing.s16),
      children: <Widget>[
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('돌려받을 수 있는 금액', style: AppTypography.captionSecondary),
              const SizedBox(height: 4),
              Text(
                formatWon(est.refundableCents ~/ 100),
                key: const ValueKey<String>('refund-estimate'),
                style: AppTypography.bigNumber,
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  AppBadge(label: est.rule, tone: AppBadgeTone.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_ruleExplain(est),
                        style: AppTypography.captionSecondary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s12),
              const _HairLine(),
              const SizedBox(height: AppSpacing.s12),
              _Line(label: '결제한 금액', value: formatWon(est.amountCents ~/ 100)),
              if (est.deductedCents > 0) ...<Widget>[
                const SizedBox(height: 6),
                _Line(
                  label: est.usageStarted && est.elapsedDays > 0
                      ? '이미 쓴 ${est.elapsedDays}일치'
                      : '기준 차감',
                  value: '-${formatWon(est.deductedCents ~/ 100)}',
                ),
              ],
              const SizedBox(height: 6),
              _Line(
                label: '환불 예정',
                value: formatWon(est.refundableCents ~/ 100),
                strong: true,
              ),
              if (est.periodEnd != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  '이번 구독 기간은 ${Formatters.monthDay(est.periodEnd!)}까지예요',
                  style: AppTypography.captionSecondary,
                ),
              ],
            ],
          ),
        ),
        if (est.isZero) ...<Widget>[
          const SizedBox(height: AppSpacing.s12),
          const AppCallout(
            tone: AppCalloutTone.warning,
            text: '기준상 환불액이 0원이에요. 신청은 할 수 있지만 돌려받는 금액은 없어요.',
          ),
        ],
        const SizedBox(height: AppSpacing.s24),
        const Text('왜 환불하시나요?', style: AppTypography.section),
        const SizedBox(height: AppSpacing.s12),
        for (final String preset in <String>[
          ...RefundRequestScreen.reasonPresets,
          RefundRequestScreen.reasonOther,
        ]) ...<Widget>[
          _ReasonRow(
            label: preset,
            selected: _reason == preset,
            onTap: _submitting ? null : () => setState(() => _reason = preset),
          ),
          const SizedBox(height: 8),
        ],
        if (_reason == RefundRequestScreen.reasonOther) ...<Widget>[
          AppField(
            label: '사유',
            help: problem == null
                ? '${RefundRequestScreen.reasonMinLength}자 이상 · ${RefundRequestScreen.reasonMaxLength}자까지'
                : null,
            error: problem,
            child: AppInputField(
              controller: _other,
              hintText: '어떤 점이 아쉬웠는지 적어 주세요',
              minLines: 3,
              maxLines: 8,
              maxLength: RefundRequestScreen.reasonMaxLength,
              enabled: !_submitting,
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_submitError != null) ...<Widget>[
          AppCallout(
            key: const ValueKey<String>('refund-error'),
            tone: AppCalloutTone.danger,
            text: _submitError!,
          ),
          const SizedBox(height: 8),
        ],
        const Text(
          '신청하면 이 구독의 새 질문이 잠기고, 관리자 확인 뒤 캐시로 돌려받아요.',
          style: AppTypography.captionSecondary,
        ),
        const SizedBox(height: AppSpacing.s16),
      ],
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = RoleTheme.of(context).color;
    return Semantics(
      button: true,
      selected: selected,
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
              Expanded(child: Text(label, style: AppTypography.body)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: AppTypography.captionSecondary)),
        Text(value, style: strong ? AppTypography.bodyStrong : AppTypography.body),
      ],
    );
  }
}

class _HairLine extends StatelessWidget {
  const _HairLine();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 1, child: ColoredBox(color: AppColors.ring));
}
