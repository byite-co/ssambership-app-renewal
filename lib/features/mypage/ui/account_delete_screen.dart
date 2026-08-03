import 'package:flutter/material.dart';

import '../../../core/auth/account_status.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/web_bridge/web_bridge_actions.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/typography_tokens.dart';
import '../../../design/widgets/money_display.dart';
import '../../../design/widgets/primary_button.dart';
import '../../../design/widgets/secondary_button.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/format/formatters.dart';
import '../data/account_deletion_repository.dart';
import '../format/cash_format.dart';

/// 회원 탈퇴(P1-10) — 위험 확인 → 서버 RPC 요청 → 로그아웃.
///
/// 흐름(서버 계약 정본):
/// - 요청: account_deletion_request_self_v2(파라미터 없음 — 취소창 30분은
///   서버 고정, dry_run 개념 폐기). 이미 job 이 있으면
///   멱등 응답(existing=true) — 이중 탭·재요청 안전.
/// - 성공 후: 토큰 revoke → 세션 폐기 → 로그인 화면(AuthService.signOut 이
///   revoke-before-signout 순서를 보장한다).
/// - 취소: 탈퇴 접수(deletionPending) 상태로 재로그인한 사용자에게만 노출.
///   판정(pending + 취소창 이내)은 전부 서버가 한다. 취소 성공 후에도 기존
///   세션 복원을 가정하지 않고 재로그인시킨다.
/// - locked/purging 이후엔 이 화면에 진입해도 취소 UI 를 만들지 않는다
///   (해당 상태는 앱 진입 자체가 차단됨 — blocked_screen).
/// ★ 42501 / RPC 미배포에서만 [AccountDeletionUnavailable] → 웹 진행 폴백.
///
/// ── 캐시 잔액 보유 계정(Build 12 실기기 FAIL 수정 — 학생/멘토 공통) ────────
/// 잔액이 남은 계정은 일반 RPC 가 `FORFEIT_CONSENT_REQUIRED` + 서버 잔액을
/// 돌려준다. 이때는 오류·웹 폴백이 아니라 **잔액 소멸 동의 단계**로 넘어간다:
///   1) 서버가 준 잔액을 그대로 표시(앱 계산·지갑 테이블 직접 조회 금지)
///   2) 소멸 시점·복구 불가·취소 가능 기간을 고지
///   3) 일반 확인과 **별도의** 잔액 소멸 동의 체크박스
///   4) 금액을 다시 적은 확인 다이얼로그
///   5) 동의 후에만 account_deletion_request_self_consented_v2 호출
/// 동의 금액이 낡으면(`FORFEIT_CONSENT_STALE`) 서버가 거절하고, 화면은 성공
/// 안내도 로그아웃도 하지 않는다(fail-closed) — 서버가 준 `current_balance_cents`
/// 로 금액을 갱신하고 동의를 다시 받는다.
///
/// ★ 소멸 시점 정본: 탈퇴 **요청** 단계는 job 과 동의 금액만 기록한다. 실제
///   캐시 몰수와 지갑 0화는 취소 가능 시간이 지난 뒤 worker 가(storage_purged
///   이후) 수행한다 — 취소창 안에서 요청을 취소하면 캐시는 소멸되지 않는다.
///   따라서 "탈퇴를 취소해도 캐시가 돌아오지 않는다"고 적지 않는다.
/// ★ 서버가 보는 잔액은 역할과 무관하게 `public.cash_wallets.balance_cents`
///   하나다(멘토 수익·지급·정산 원장이 아니다) → 학생·멘토 모두 '캐시 잔액'.
class AccountDeleteScreen extends StatefulWidget {
  const AccountDeleteScreen({
    super.key,
    this.port = const SupabaseAccountDeletionRepository(),
    this.signOutOverride,
    this.openWebFallbackOverride,
    this.pendingOverride,
  });

  final AccountDeletionPort port;

  /// 테스트 주입: 기본은 AuthService.instance.signOut(revoke → signOut 보장).
  final Future<void> Function()? signOutOverride;

  /// 테스트 주입: 기본은 웹브리지 /account/delete 열기.
  final Future<void> Function(BuildContext context)? openWebFallbackOverride;

  /// 테스트 주입: 탈퇴 접수(deletionPending) 상태 여부. null 이면 AuthService.
  final bool? pendingOverride;

  @override
  State<AccountDeleteScreen> createState() => _AccountDeleteScreenState();
}

class _AccountDeleteScreenState extends State<AccountDeleteScreen> {
  bool _acknowledged = false;
  bool _busy = false;

  /// 서버가 취소 불가(창 경과/처리 진행)를 알려온 뒤에는 취소 버튼을 없앤다.
  bool _cancelClosed = false;

  /// 42501/미배포 — 앱 경로 미개방 → 웹 폴백 카드 노출.
  bool _unavailable = false;

  /// 서버 `cancelable_until` 정본. null 이면 시각을 표시하지 않는다 —
  /// ★ 클라이언트 시계로 취소 마감을 계산하지 않는다(로컬 추정 금지).
  DateTime? _cancelableUntil;

  /// 서버가 준 소멸 예정 잔액(cents). null 이면 아직 동의 단계가 아니다.
  /// ★ 이 값은 서버 응답 원본이며 앱이 만들거나 고치지 않는다.
  int? _forfeitBalanceCents;

  /// 잔액 소멸 **전용** 동의. 일반 확인(_acknowledged)과 절대 겸용하지 않는다.
  bool _forfeitAcknowledged = false;

  bool get _consentStage => _forfeitBalanceCents != null;

  bool get _pending =>
      widget.pendingOverride ??
      AuthService.instance.accountState.kind ==
          AccountStatusKind.deletionPending;

  @override
  void initState() {
    super.initState();
    if (_pending) _loadStatus();
  }

  /// pending 진입 시 서버 판정(can_cancel)으로 취소 버튼 노출을 확정한다.
  /// (취소창 경과·locked 이후엔 버튼 자체를 만들지 않음 — 로컬 추정 금지.)
  Future<void> _loadStatus() async {
    try {
      final DeletionStatusResult s = await widget.port.fetchStatus();
      if (!mounted) return;
      setState(() {
        _cancelableUntil = s.cancelableUntil; // 서버 정본 시각(있을 때만 표시)
        if (!s.canCancel) _cancelClosed = true;
      });
    } on AccountDeletionUnavailable {
      if (mounted) setState(() => _unavailable = true);
    } catch (_) {
      // 조회 실패 → 버튼은 유지하되 실제 취소는 서버가 재판정한다.
    }
  }

  Future<void> _signOut() =>
      (widget.signOutOverride ?? AuthService.instance.signOut)();

  Future<void> _openWeb() =>
      (widget.openWebFallbackOverride ?? openAccountDeleteWeb)(context);

  /// 탈퇴 요청 — 성공(신규/멱등 공통) 시 안내 후 로그아웃.
  ///
  /// ★ 이중 탭 방지: 확인 다이얼로그를 띄우기 **전에** 동기적으로 _busy 를 세운다.
  ///   (다이얼로그 await 뒤에 세우면 연타가 가드를 통과해 요청이 2번 나간다.)
  Future<void> _request() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bool ok = await _confirm(
        '정말 탈퇴할까요?',
        // 아직 접수 전이라 서버 마감 시각이 없다 — 시간을 명시하지 않는다.
        '탈퇴하면 계정과 데이터가 삭제되며 되돌릴 수 없어요.\n'
            '접수 후 취소 가능 시간 내에는 취소할 수 있어요.',
        '탈퇴 요청',
      );
      if (!ok || !mounted) return;
      await _submit(widget.port.requestDeletion());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 잔액 소멸 동의 후 탈퇴 요청 — 동의한 금액(서버 원본)을 그대로 되돌려준다.
  Future<void> _requestWithForfeitConsent() async {
    if (_busy) return;
    final int? balance = _forfeitBalanceCents;
    // 동의 체크 없이는 절대 consent RPC 를 부르지 않는다(버튼 비활성 + 여기서 재확인).
    if (balance == null || !_forfeitAcknowledged) return;
    setState(() => _busy = true);
    try {
      final bool ok = await _confirm(
        '캐시 잔액 ${CashFormat.won(balance)}이 소멸돼요',
        '취소 가능 시간이 지나 삭제 처리가 시작되면 남은 캐시 잔액 '
            '${CashFormat.won(balance)}이 소멸되고 되돌릴 수 없어요.\n'
            '계정과 데이터도 함께 삭제돼요.\n'
            '취소 가능 시간 내에는 탈퇴 요청을 취소할 수 있어요.',
        '동의하고 탈퇴',
      );
      if (!ok || !mounted) return; // 취소 → consent RPC 0회.
      await _submit(widget.port.requestDeletionWithForfeitConsent(
        acknowledgedBalanceCents: balance,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 요청 RPC 2종 공통 후처리. **접수 확정(DeletionAccepted)일 때만** 성공 안내와
  /// 로그아웃을 한다 — 그 외 분기에선 성공 화면도 signOut 도 만들지 않는다.
  Future<void> _submit(Future<DeletionRequestOutcome> call) async {
    try {
      final DeletionRequestOutcome outcome = await call;
      if (!mounted) return;
      switch (outcome) {
        case DeletionAccepted(result: final DeletionRequestResult r):
          await _showDone(
            r.isPending
                ? '탈퇴 요청이 접수됐어요.\n${_cancelWindowLine(r.cancelableUntil)}\n'
                    '보안을 위해 로그아웃돼요.'
                : '이미 탈퇴 처리가 진행 중인 계정이에요.\n보안을 위해 로그아웃돼요.',
          );
          await _signOut(); // 토큰 revoke → 세션 폐기(내부 순서 보장) → 로그인 화면.

        case DeletionForfeitConsentRequired(balanceCents: final int cents):
          // 오류가 아니다 — 웹 폴백도, 실패 스낵바도 띄우지 않고 동의 단계로 간다.
          setState(() {
            _forfeitBalanceCents = cents;
            _forfeitAcknowledged = false; // 금액이 바뀌었을 수 있다 → 동의 재취득.
          });

        case DeletionBalanceMismatch(serverBalanceCents: final int? cents):
          // TOCTOU — 접수되지 않았다. 성공 화면·로그아웃 없음.
          setState(() {
            _forfeitAcknowledged = false;
            if (cents != null && cents > 0) _forfeitBalanceCents = cents;
            // 새 잔액을 서버가 안 알려줬으면 처음부터 다시(임의 추정 금지).
            if (cents == null || cents <= 0) _forfeitBalanceCents = null;
          });
          _snack(cents != null && cents > 0
              ? '남은 캐시 잔액이 ${CashFormat.won(cents)}으로 바뀌었어요. '
                  '다시 확인하고 동의해 주세요.'
              : '남은 캐시 잔액이 변경돼 탈퇴를 접수하지 못했어요. 다시 시도해 주세요.');
      }
    } on AccountDeletionUnavailable {
      if (mounted) setState(() => _unavailable = true);
    } catch (e) {
      // 네트워크·서버 오류 — 웹 폴백으로 위장하지 않는다.
      _snack('탈퇴 요청에 실패했어요. ${friendlyError(e)}');
    }
  }

  /// 탈퇴 취소 — 서버 판정(pending + 취소창 이내)만 신뢰.
  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final DeletionCancelResult result = await widget.port.cancelDeletion();
      if (!mounted) return;
      if (result.ok) {
        // 기존 세션이 완전히 복원됐다고 가정하지 않는다 — 재로그인 요구.
        await _showDone('탈퇴가 취소됐어요.\n다시 로그인해 주세요.');
        await _signOut();
        return;
      }
      if (result.windowPassed) {
        setState(() => _cancelClosed = true);
        _snack('취소 가능 시간이 지났어요. 탈퇴가 예정대로 진행돼요.');
      } else if (result.notCancelable) {
        setState(() => _cancelClosed = true);
        _snack('이미 처리 중이라 취소할 수 없어요.');
      } else {
        _snack('취소할 탈퇴 요청이 없어요.');
      }
    } on AccountDeletionUnavailable {
      if (mounted) setState(() => _unavailable = true);
    } catch (e) {
      _snack('취소에 실패했어요. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 취소 가능 구간 안내 — **서버 `cancelable_until` 이 있을 때만** 시각을
  /// 적는다. 값이 없으면 시간 미명시 중립 문구로 돌아간다(로컬 재계산 금지).
  static String _cancelWindowLine(DateTime? until) => until != null
      ? '${Formatters.dateTimeMinute(until)}까지 다시 로그인해 취소할 수 있어요.'
      : '취소 가능 시간 내에는 다시 로그인해 취소할 수 있어요.';

  Future<bool> _confirm(String title, String body, String action) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('돌아가기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: ColorTokens.danger),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _showDone(String message) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원 탈퇴')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH, vertical: AppSpacing.s16),
        children: <Widget>[
          if (_pending)
            ..._pendingBody()
          else if (_consentStage)
            ..._forfeitConsentBody()
          else
            ..._requestBody(),
          if (_unavailable) ...<Widget>[
            const SizedBox(height: AppSpacing.s16),
            Text(
              '앱에서 바로 탈퇴할 수 없어요.\n웹 페이지에서 탈퇴를 진행해 주세요.',
              style: AppType.body.copyWith(color: ColorTokens.danger),
            ),
            const SizedBox(height: 8),
            SecondaryButton(label: '웹에서 진행', onPressed: () => _openWeb()),
          ],
        ],
      ),
    );
  }

  List<Widget> _requestBody() {
    return <Widget>[
      Text('탈퇴 전에 꼭 확인해 주세요', style: AppType.title),
      const SizedBox(height: AppSpacing.s16),
      const Text(
        // 접수 전에는 서버 마감 시각이 없다 — 구체 시각은 접수 후 안내·배너가 낸다.
        // 잔액도 아직 서버에 묻기 전이라 금액을 적지 않는다(앱 추정 금지) —
        // 남아 있으면 요청 시 서버가 알려주고 별도 동의 단계로 넘어간다.
        '· 계정과 프로필, 질문/답변 기록이 삭제돼요.\n'
        '· 삭제 후에는 되돌릴 수 없어요.\n'
        '· 접수 후 취소 가능 시간 내에만 취소할 수 있어요.\n'
        '· 남은 캐시 잔액이 있으면 삭제 처리와 함께 소멸돼요.',
        style: AppType.body,
      ),
      const SizedBox(height: AppSpacing.s16),
      CheckboxListTile(
        value: _acknowledged,
        onChanged: _busy
            ? null
            : (bool? v) => setState(() => _acknowledged = v ?? false),
        title: const Text('위 내용을 모두 확인했어요', style: AppType.body),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: AppSpacing.s16),
      PrimaryButton(
        label: _busy ? '처리 중…' : '탈퇴 요청',
        onPressed: (_acknowledged && !_busy && !_unavailable) ? _request : null,
      ),
    ];
  }

  /// 잔액 소멸 동의 단계 — 서버가 `FORFEIT_CONSENT_REQUIRED` 와 함께 준 잔액을
  /// 그대로 보여주고, 일반 확인과 **별도의** 동의를 받는다.
  List<Widget> _forfeitConsentBody() {
    final int balance = _forfeitBalanceCents!;
    return <Widget>[
      Text('남은 캐시 잔액이 있어요', style: AppType.title),
      const SizedBox(height: AppSpacing.s16),
      // 금액은 서버 응답(balance_cents) 정본 — 앱에서 계산하지 않는다.
      MoneyDisplay(
        label: '삭제 처리 시 소멸되는 캐시 잔액',
        amount: CashFormat.won(balance),
        emphasizeColor: ColorTokens.danger,
      ),
      const SizedBox(height: AppSpacing.s16),
      Text(
        // 소멸 시점 정본: 요청 단계는 job·동의 금액만 기록하고, 실제 몰수와
        // 지갑 0화는 취소창이 지난 뒤 worker(storage_purged 이후)가 수행한다.
        // → "탈퇴를 취소해도 캐시가 돌아오지 않는다"는 서버 동작과 다르다.
        '· 취소 가능 시간이 지나 삭제 처리가 시작되면 남은 캐시 잔액 '
        '${CashFormat.won(balance)}이 소멸돼요.\n'
        '· 소멸 처리 후에는 환불·복구할 수 없어요.\n'
        '· 취소 가능 시간 내에 탈퇴 요청을 취소하면 캐시 잔액은 소멸되지 않아요.',
        style: AppType.body,
      ),
      const SizedBox(height: AppSpacing.s16),
      CheckboxListTile(
        value: _forfeitAcknowledged,
        onChanged: _busy
            ? null
            : (bool? v) => setState(() => _forfeitAcknowledged = v ?? false),
        title: Text(
          '삭제 처리 시 남은 캐시 잔액 ${CashFormat.won(balance)}이 소멸되는 데 동의해요',
          style: AppType.body,
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: AppSpacing.s16),
      PrimaryButton(
        label: _busy ? '처리 중…' : '동의하고 탈퇴 요청',
        onPressed: (_forfeitAcknowledged && !_busy && !_unavailable)
            ? _requestWithForfeitConsent
            : null,
      ),
      const SizedBox(height: AppSpacing.s8),
      SecondaryButton(
        label: '돌아가기',
        neutral: true,
        onPressed: _busy
            ? null
            : () => setState(() {
                  _forfeitBalanceCents = null;
                  _forfeitAcknowledged = false;
                }),
      ),
    ];
  }

  List<Widget> _pendingBody() {
    return <Widget>[
      Text('탈퇴 요청이 접수된 계정이에요', style: AppType.title),
      const SizedBox(height: AppSpacing.s16),
      Text(
        // 서버 status_self 의 cancelable_until 정본을 그대로 표시한다.
        '${_cancelWindowLine(_cancelableUntil)}\n'
        '취소하면 보안을 위해 다시 로그인해야 해요.',
        style: AppType.body,
      ),
      const SizedBox(height: AppSpacing.s16),
      if (!_cancelClosed)
        PrimaryButton(
          label: _busy ? '처리 중…' : '탈퇴 취소',
          onPressed: _busy ? null : _cancel,
        )
      else
        const Text(
          '지금은 취소할 수 없어요. 탈퇴가 예정대로 진행돼요.',
          style: AppType.body,
        ),
    ];
  }
}
