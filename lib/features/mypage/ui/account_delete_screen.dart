import 'package:flutter/material.dart';

import '../../../core/auth/account_status.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/web_bridge/web_bridge_actions.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/typography_tokens.dart';
import '../../../design/widgets/primary_button.dart';
import '../../../design/widgets/secondary_button.dart';
import '../../../shared/errors/friendly_error.dart';
import '../../../shared/format/formatters.dart';
import '../data/account_deletion_repository.dart';

/// 회원 탈퇴(P1-10) — 위험 확인 → 서버 RPC 요청 → 로그아웃.
///
/// 흐름(서버 계약 정본):
/// - 요청: account_deletion_request(dry_run=false 명시). 이미 job 이 있으면
///   멱등 응답(existing=true) — 이중 탭·재요청 안전.
/// - 성공 후: 토큰 revoke → 세션 폐기 → 로그인 화면(AuthService.signOut 이
///   revoke-before-signout 순서를 보장한다).
/// - 취소: 탈퇴 접수(deletionPending) 상태로 재로그인한 사용자에게만 노출.
///   판정(pending + 취소창 이내)은 전부 서버가 한다. 취소 성공 후에도 기존
///   세션 복원을 가정하지 않고 재로그인시킨다.
/// - locked/purging 이후엔 이 화면에 진입해도 취소 UI 를 만들지 않는다
///   (해당 상태는 앱 진입 자체가 차단됨 — blocked_screen).
/// ★ 스테이징 현재 RPC 가 service_role 전용이라 앱 호출은 42501 →
///   [AccountDeletionUnavailable] 분기에서 웹 진행 폴백을 안내한다(WAITING_SERVER_API).
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

  /// 42501 — 앱 경로 미개방 → 웹 폴백 카드 노출(self RPC 미배포 환경 방어).
  bool _unavailable = false;

  /// 서버 `cancelable_until` 정본. null 이면 시각을 표시하지 않는다 —
  /// ★ 클라이언트 시계로 취소 마감을 계산하지 않는다(로컬 추정 금지).
  DateTime? _cancelableUntil;

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
  Future<void> _request() async {
    if (_busy) return;
    final bool ok = await _confirm(
      '정말 탈퇴할까요?',
      // 아직 접수 전이라 서버 마감 시각이 없다 — 시간을 명시하지 않는다.
      '탈퇴하면 계정과 데이터가 삭제되며 되돌릴 수 없어요.\n'
          '접수 후 취소 가능 시간 내에는 취소할 수 있어요.',
      '탈퇴 요청',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final DeletionRequestResult result = await widget.port.requestDeletion();
      if (!mounted) return;
      // 실패 시 성공 화면·로컬 성공 상태를 만들지 않는다 — 여기 도달 = 서버 접수 확정.
      await _showDone(
        result.isPending
            ? '탈퇴 요청이 접수됐어요.\n${_cancelWindowLine(result.cancelableUntil)}\n'
                '보안을 위해 로그아웃돼요.'
            : '이미 탈퇴 처리가 진행 중인 계정이에요.\n보안을 위해 로그아웃돼요.',
      );
      await _signOut(); // 토큰 revoke → 세션 폐기(내부 순서 보장) → 로그인 화면.
    } on AccountDeletionUnavailable {
      if (mounted) setState(() => _unavailable = true);
    } catch (e) {
      _snack('탈퇴 요청에 실패했어요. ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
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
          if (_pending) ..._pendingBody() else ..._requestBody(),
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
        '· 계정과 프로필, 질문/답변 기록이 삭제돼요.\n'
        '· 삭제 후에는 되돌릴 수 없어요.\n'
        '· 접수 후 취소 가능 시간 내에만 취소할 수 있어요.\n'
        '· 남은 캐시·구독은 웹 고객센터 안내를 따라 주세요.',
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
