import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../design/tokens/app_colors.dart';
import '../../../design/tokens/app_spacing.dart';
import '../../../design/tokens/app_typography.dart';
import '../../../design/widgets/app_input_field.dart';
import '../../../design/widgets/app_primary_button.dart';
import '../../../design/widgets/glass_card.dart';
import '../../../design/widgets/glass_inner.dart';
import '../../../design/role_theme.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../design/widgets/app_page.dart';
import '../../../design/widgets/app_blocks.dart';
import '../data/mentor_console_models.dart';
import '../data/mentor_console_repository.dart';
import '../data/payout_bank_allowlist.dart';

/// 정산 계좌 등록(A-4a #1) — `/settlements/account`.
///
/// 은행(allowlist 17종 시트) · 계좌번호(숫자 8~24) · 예금주(본인 실명 고정 표시).
/// 저장은 `api_web_v1.mentor_payout_account_update_self`(F13) 한 경로다 —
/// 승인 멘토·은행·계좌 형식 판정은 DB 정본이고 앱은 사전 안내·버튼 비활성만 한다.
/// 계좌 원문은 입력 컨트롤러에만 있고 성공 후엔 마스킹 값만 남긴다.
class PayoutAccountScreen extends StatefulWidget {
  const PayoutAccountScreen({super.key, this.portOverride});

  /// 테스트·골든용 포트 주입. null 이면 AppScope 의 운영 의존성.
  final MentorConsolePort? portOverride;

  @override
  State<PayoutAccountScreen> createState() => _PayoutAccountScreenState();
}

class _PayoutAccountLoad {
  const _PayoutAccountLoad({required this.current, required this.fullName});
  final PayoutAccountInfo current;
  final String? fullName;
}

class _PayoutAccountScreenState extends State<PayoutAccountScreen> {
  late final MentorConsolePort _port;
  late Future<_PayoutAccountLoad> _future;
  final TextEditingController _account = TextEditingController();

  String? _bank;
  bool _saving = false;

  /// 마지막 저장 실패 문구(폼 위 인라인). 성공하면 null.
  String? _saveError;

  /// 저장 성공 후 갱신된 현재 계좌(마스킹).
  PayoutAccountInfo? _saved;

  @override
  void initState() {
    super.initState();
    _port = widget.portOverride ?? AppScope.of(context).mentorConsole;
    _future = _load();
    _account.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  Future<_PayoutAccountLoad> _load() async {
    final List<dynamic> r = await Future.wait(<Future<dynamic>>[
      _port.loadPayoutAccount(),
      _port.loadFullName(),
    ]);
    final PayoutAccountInfo current = r[0] as PayoutAccountInfo;
    // 이미 등록된 은행은 선택값으로 미리 채운다(계좌번호는 원문이 없으므로 비움).
    if (_bank == null && current.bankName != null &&
        kPayoutBankAllowlist.contains(current.bankName)) {
      _bank = current.bankName;
    }
    return _PayoutAccountLoad(current: current, fullName: r[1] as String?);
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  String get _digits => payoutAccountDigits(_account.text);

  bool get _accountValid => kPayoutAccountNumberPattern.hasMatch(_digits);

  bool get _canSubmit => !_saving && _bank != null && _accountValid;

  Future<void> _pickBank() async {
    final String? picked = await showAppBottomSheet<String>(
      context,
      builder: (BuildContext ctx) => _BankPickerSheet(selected: _bank),
    );
    if (picked != null && mounted) setState(() => _bank = picked);
  }

  Future<void> _submit() async {
    final String? bank = _bank;
    if (bank == null || !_accountValid || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final PayoutAccountInfo saved = await _port.updatePayoutAccount(
        bankName: bank,
        accountNumber: _digits,
      );
      if (!mounted) return;
      _account.clear(); // 원문은 즉시 폐기 — 화면엔 마스킹만 남긴다.
      setState(() => _saved = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정산 계좌를 등록했어요.')),
      );
      Navigator.of(context).maybePop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveError = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: '정산 계좌',
      body: FutureBuilder<_PayoutAccountLoad>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<_PayoutAccountLoad> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppLoadingView(cards: 2);
          }
          if (snap.hasError || snap.data == null) {
            return AppErrorView(
              title: '계좌 정보를 불러오지 못했어요',
              message: friendlyError(snap.error ?? ''),
              onRetry: _retry,
            );
          }
          return _form(context, snap.data!);
        },
      ),
    );
  }

  Widget _form(BuildContext context, _PayoutAccountLoad data) {
    final PayoutAccountInfo current = _saved ?? data.current;
    final String? accountError = _account.text.isEmpty || _accountValid
        ? null
        : '계좌번호는 숫자 8~24자리로 입력해 주세요.';
    return ListView(
      padding: AppPage.contentPadding(context),
      children: <Widget>[
        if (current.registered)
          AppCallout(
            tone: AppCalloutTone.success,
            title: '등록된 계좌',
            text: '${current.bankName} ${current.accountMasked}',
          )
        else
          const AppCallout(
            tone: AppCalloutTone.warning,
            title: '아직 계좌가 없어요',
            text: '계좌를 등록하지 않으면 매달 23일 지급이 다음 달로 미뤄져요.',
          ),
        const SizedBox(height: AppSpacing.base),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppField(
                label: '은행',
                child: _BankSelectRow(bank: _bank, onTap: _saving ? null : _pickBank),
              ),
              const SizedBox(height: AppSpacing.base),
              AppField(
                label: '계좌번호',
                help: '숫자만 8~24자리 · 하이픈 없이 입력해요',
                error: accountError,
                child: AppInputField(
                  controller: _account,
                  hintText: '계좌번호',
                  keyboardType: TextInputType.number,
                  enabled: !_saving,
                ),
              ),
              const SizedBox(height: AppSpacing.base),
              AppField(
                label: '예금주',
                help: '본인 실명으로 고정돼요. 다른 사람 계좌는 등록할 수 없어요.',
                child: GlassInner(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          data.fullName ?? '실명 확인 필요',
                          style: AppTypography.body.copyWith(
                            color: data.fullName == null
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_saveError != null) ...<Widget>[
          const SizedBox(height: 12),
          AppCallout(tone: AppCalloutTone.danger, text: _saveError!),
        ],
        const SizedBox(height: AppSpacing.section),
        AppPrimaryButton(
          label: _saving
              ? '등록 중…'
              : (current.registered ? '계좌 변경하기' : '등록하기'),
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: 8),
        Text(
          '정산은 매달 23일 전달 확정분을 이 계좌로 보내요.',
          textAlign: TextAlign.center,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _BankSelectRow extends StatelessWidget {
  const _BankSelectRow({required this.bank, required this.onTap});

  final String? bank;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    return Semantics(
      button: true,
      label: '은행 선택',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: GlassInner(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ringColor: bank == null ? null : roleTheme.color.withValues(alpha: 0.45),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  bank ?? '은행을 선택해 주세요',
                  style: AppTypography.body.copyWith(
                    color: bank == null
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.expand_more_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 은행 allowlist 시트 — 17종 고정 목록. 검색 없이 한 손 스크롤.
class _BankPickerSheet extends StatelessWidget {
  const _BankPickerSheet({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(bottom: 8, top: 4),
          child: Text('은행 선택', style: AppTypography.section),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final String bank in kPayoutBankAllowlist)
                InkWell(
                  onTap: () => Navigator.of(context).pop(bank),
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 13,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            bank,
                            style: AppTypography.body.copyWith(
                              fontWeight: bank == selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: bank == selected
                                  ? roleTheme.color
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (bank == selected)
                          Icon(Icons.check_rounded, size: 20, color: roleTheme.color),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
