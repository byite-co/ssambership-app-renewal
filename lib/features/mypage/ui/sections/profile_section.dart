import 'package:flutter/material.dart';

import '../../../../design/tokens/app_colors.dart';
import '../../../../design/tokens/app_typography.dart';
import '../../../../design/widgets/initial_avatar.dart';
import '../../data/mypage_models.dart';

/// 프로필 헤더(이름·역할·이메일·학년). 값이 없으면 비운다(하드코딩/날조 없음).
class ProfileSection extends StatelessWidget {
  const ProfileSection({super.key, required this.profile, this.onEdit});

  final MyProfile profile;

  /// 프로필 수정 진입(없으면 수정 버튼 비표시 — 예: 게스트).
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final List<String> sub = <String>[
      if (profile.roleLabel.isNotEmpty) profile.roleLabel,
      if (profile.grade != null) profile.grade!,
    ];
    return Row(
      children: <Widget>[
        InitialAvatar(name: profile.name, size: 56, tinted: false),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                profile.name.isNotEmpty ? profile.name : '내 정보',
                style: AppTypography.title,
              ),
              if (sub.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(sub.join(' · '), style: AppTypography.captionSecondary),
              ],
              if (profile.email != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(profile.email!, style: AppTypography.meta),
              ],
            ],
          ),
        ),
        if (onEdit != null)
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
            tooltip: '프로필 수정',
            color: AppColors.textSecondary,
          ),
      ],
    );
  }
}
