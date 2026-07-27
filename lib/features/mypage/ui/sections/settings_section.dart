import 'package:flutter/material.dart';

import '../../../../core/push/push_ports.dart';
import '../../../../core/web_bridge/web_bridge_actions.dart';
import '../../../../design/role_accent.dart';
import '../../../../design/tokens/color_tokens.dart';
import '../../../../design/typography_tokens.dart';
import '../../../../design/widgets/secondary_button.dart';
import '../../../../features/community/ui/blocks/blocked_users_screen.dart';
import '../../../../shared/constants/app_constants.dart';
import '../../../../shared/errors/friendly_error.dart';
import '../../data/notification_settings_repository.dart';
import '../account_delete_screen.dart';
import '../widgets/mypage_section.dart';

/// 설정 섹션 — 알림 설정(마스터+그룹별)·약관/개인정보·앱 버전·로그아웃.
///
/// 알림 설정은 정본 테이블(notification_settings)에서 로드/저장:
/// - 로드 실패 → 기본값 위장 없이 '다시 시도' 안내.
/// - 토글은 낙관적 반영 후 저장 실패 시 원복 + 스낵바(재시도 가능).
/// - OS 알림 권한 거부는 서버 설정과 '별개'의 안내로만 표시(요청은 푸시 라인 소관).
class SettingsSection extends StatefulWidget {
  const SettingsSection({
    super.key,
    required this.onLogout,
    this.showLogout = true,
    this.settingsRepository = const NotificationSettingsRepository(),
    this.permissionPort = const DisabledPushPermission(),
  });

  /// 로그아웃 동작(기본: AuthService.signOut). 화면에서 주입.
  final VoidCallback onLogout;

  /// 실제 세션이 있을 때만 로그아웃 노출(게스트 방어).
  final bool showLogout;

  /// 알림 설정 저장소(테스트: 페이크 주입).
  final NotificationSettingsPort settingsRepository;

  /// OS 알림 권한 조회 포트(기본: 미연결 Disabled — 요청은 하지 않는다).
  final PushPermissionPort permissionPort;

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  /// 로드 결과 3상태: 로딩(null·에러 null) / 성공(settings) / 실패(error).
  NotificationSettings? _settings;
  Object? _loadError;
  bool _loading = true;

  /// 저장 중이면 토글 잠금(중복 저장 방지).
  bool _saving = false;

  PushPermissionStatus _permission = PushPermissionStatus.notDetermined;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    // OS 권한은 별도 조회 — 실패해도 설정 로드와 무관(미결정 유지).
    try {
      final PushPermissionStatus p = await widget.permissionPort.current();
      if (mounted) setState(() => _permission = p);
    } catch (_) {}
    try {
      final NotificationSettings s = await widget.settingsRepository.load();
      if (!mounted) return;
      setState(() {
        _settings = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e; // ★ 기본값(전부 ON)으로 위장하지 않는다.
        _loading = false;
      });
    }
  }

  /// 낙관적 반영 → 저장 실패 시 원복 + 스낵바. 성공해야만 값이 확정된다.
  Future<void> _saveWith(NotificationSettings next) async {
    final NotificationSettings? prev = _settings;
    if (prev == null || _saving) return;
    setState(() {
      _settings = next;
      _saving = true;
    });
    try {
      await widget.settingsRepository.save(next);
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _settings = prev; // 원복 — 화면이 저장 안 된 값을 진실처럼 두지 않는다.
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('알림 설정 저장에 실패했어요. ${friendlyError(e)}')),
      );
    }
  }

  /// 회원 탈퇴 — 인앱 탈퇴 화면(P1-10)으로 진입한다.
  /// 위험 고지·재확인·서버 RPC 요청·취소·웹 폴백은 전부 AccountDeleteScreen 담당.
  Future<void> _confirmAccountDelete() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AccountDeleteScreen(),
      ),
    );
  }

  // ── 알림 설정 영역 ──────────────────────────────────────────────

  Widget _notificationArea(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_loadError != null) {
      // 로드 실패 — 기본값을 진실처럼 보여주지 않고 재시도만 노출.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '알림 설정을 불러오지 못했어요. ${friendlyError(_loadError!)}',
              style: AppType.caption.copyWith(color: ColorTokens.danger),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _load,
                child: const Text('다시 시도'),
              ),
            ),
          ],
        ),
      );
    }
    final NotificationSettings s = _settings!;
    final Color accent = AppAccent.of(context).accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // OS 권한 거부 안내 — 서버 토글과 별개(끄기 상태와 혼동 금지).
        if (_permission == PushPermissionStatus.denied)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '기기 알림 권한이 꺼져 있어요 — 설정에서 허용해 주세요.',
              style: AppType.caption.copyWith(color: ColorTokens.danger),
            ),
          ),
        _toggleRow(
          label: '알림 받기',
          value: s.pushEnabled,
          accent: accent,
          onChanged: _saving
              ? null
              : (bool v) => _saveWith(s.copyWith(pushEnabled: v)),
        ),
        // 그룹별 토글 — 마스터가 꺼져 있으면 서버가 전부 차단하므로 잠근다.
        for (final String key in NotificationGroups.keys)
          _toggleRow(
            label: NotificationGroups.labelOf(key),
            value: s.groupEnabled(key),
            accent: accent,
            indent: true,
            onChanged: (_saving || !s.pushEnabled)
                ? null
                : (bool v) => _saveWith(s.withGroup(key, v)),
          ),
      ],
    );
  }

  Widget _toggleRow({
    required String label,
    required bool value,
    required Color accent,
    required ValueChanged<bool>? onChanged,
    bool indent = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? 12 : 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: indent ? AppType.caption : AppType.body),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: accent,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MyPageSection(
      icon: Icons.settings_rounded,
      title: '설정',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _notificationArea(context),
          const Divider(height: 12, color: ColorTokens.border),
          MyPageRow(
            icon: Icons.description_rounded,
            label: '이용약관',
            onTap: () => openTermsWeb(context),
          ),
          MyPageRow(
            icon: Icons.privacy_tip_rounded,
            label: '개인정보 처리방침',
            onTap: () => openPrivacyWeb(context),
          ),
          const MyPageRow(
            icon: Icons.info_rounded,
            label: '앱 버전',
            trailingText: AppConstants.appVersion,
            showChevron: false,
          ),
          // 계정: 차단 관리(앱 내) + 회원 탈퇴(웹 링크). 로그인 세션일 때만 노출.
          if (widget.showLogout) ...<Widget>[
            const Divider(height: 12, color: ColorTokens.border),
            MyPageRow(
              icon: Icons.block_rounded,
              label: '차단 관리',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const BlockedUsersScreen(),
                ),
              ),
            ),
            MyPageRow(
              icon: Icons.person_remove_rounded,
              label: '회원 탈퇴',
              onTap: _confirmAccountDelete,
            ),
            const SizedBox(height: 12),
            SecondaryButton(
              label: '로그아웃',
              icon: Icons.logout_rounded,
              onPressed: widget.onLogout,
            ),
          ],
        ],
      ),
    );
  }
}
