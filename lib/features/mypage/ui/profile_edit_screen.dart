import 'package:flutter/material.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/web_bridge/web_bridge_actions.dart';
import '../../../design/tokens/color_tokens.dart';
import '../../../design/shape_tokens.dart';
import '../../../design/spacing_tokens.dart';
import '../../../design/typography_tokens.dart';
import '../../../design/widgets/primary_button.dart';
import '../../../design/widgets/secondary_button.dart';
import '../data/mypage_models.dart';
import '../data/profile_edit_repository.dart';
import '../../../shared/errors/friendly_error.dart';

/// 프로필 수정 — 안전 필드(표시명·학년)만 편집. 역할·이메일·id 는 편집 대상 아님(표시만/제외).
/// ★ 프로필 이미지는 Storage 버킷 의존이라 이번 범위 밖(버킷 준비 후 별도) — 텍스트 필드는 즉시 작동.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    required this.profile,
    this.repository = const ProfileEditRepository(),
  });

  final MyProfile profile;
  final ProfileEditRepository repository;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.name);
  late final TextEditingController _grade =
      TextEditingController(text: widget.profile.grade ?? '');
  bool _busy = false;

  /// 역할 분기: 멘토는 학년 필드가 없고(웹에서 상세 관리), 학생만 학년을 편집한다.
  bool get _isMentor => AuthService.instance.currentRole == AppRole.mentor;

  @override
  void dispose() {
    _name.dispose();
    _grade.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    final String grade = _grade.text.trim();
    if (name.isEmpty) {
      _snack('표시명을 입력해 주세요.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.updateProfile(
        nickname: name,
        // 멘토는 p_grade_level 을 payload 에서 제외(null → 레포가 파라미터 생략).
        // 학생이 학년을 비웠으면 ''(빈 문자열) 를 보내 서버가 NULL 로 비운다 —
        // 생략(유지)과 비우기를 구분하는 서버 계약이다.
        gradeLevel: _isMentor ? null : grade,
      );
      if (!mounted) return;
      _snack('프로필을 저장했어요.');
      Navigator.of(context).pop(true); // 저장됨 → 마이페이지가 새로고침.
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('저장에 실패했어요. ${friendlyError(e)}');
      }
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('프로필 수정')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH, vertical: AppSpacing.s16),
        children: <Widget>[
          Text('표시명', style: AppType.caption),
          const SizedBox(height: AppSpacing.titleBody),
          TextField(
            controller: _name,
            style: AppType.body,
            decoration: _decoration('표시할 이름'),
          ),
          // 학년은 학생만 편집(멘토는 학년 개념 없음 — 웹 프로필 관리로 연결).
          if (!_isMentor) ...<Widget>[
            const SizedBox(height: AppSpacing.s16),
            Text('학년 (선택)', style: AppType.caption),
            const SizedBox(height: AppSpacing.titleBody),
            TextField(
              controller: _grade,
              style: AppType.body,
              decoration: _decoration('예: 고2, 재수생'),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          // 역할·이메일은 편집 대상이 아님(안내만).
          if (widget.profile.email != null)
            Text('이메일 ${widget.profile.email} · 역할·이메일은 여기서 바꿀 수 없어요.',
                style: AppType.caption),
          const SizedBox(height: AppSpacing.s24),
          PrimaryButton(
            label: _busy ? '저장 중…' : '저장',
            onPressed: _busy ? null : _save,
          ),
          // 멘토: 상세 프로필(대학·학과·소개 등)은 웹에서 관리.
          if (_isMentor) ...<Widget>[
            const SizedBox(height: AppSpacing.s12),
            SecondaryButton(
              label: '멘토 프로필 관리 (웹)',
              icon: Icons.open_in_new_rounded,
              neutral: true,
              onPressed: () => openProfileEditWeb(context),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: ColorTokens.elevated,
      border: OutlineInputBorder(
        borderRadius: AppShape.inputRadius,
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
