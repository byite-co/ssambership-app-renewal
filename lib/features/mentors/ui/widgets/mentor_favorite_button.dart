import 'package:flutter/material.dart';

import '../../../../design/role_theme.dart';
import '../../../../design/tokens/app_colors.dart';

/// 멘토 찜 토글 하트 — 카드·상세 공용. 찜=역할색(학생 파랑) 채움, 미찜=외곽선(보조색).
/// ★ 표현 전용: 상태(찜 여부)와 탭 콜백만 받는다(데이터/RLS는 호출부/레포 담당).
class MentorFavoriteButton extends StatelessWidget {
  const MentorFavoriteButton({
    super.key,
    required this.favorited,
    required this.onTap,
    this.size = 22,
  });

  final bool favorited;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color accent = RoleTheme.of(context).color;
    return IconButton(
      onPressed: onTap,
      iconSize: size,
      visualDensity: VisualDensity.compact,
      tooltip: favorited ? '찜 해제' : '찜하기',
      icon: Icon(
        favorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: favorited ? accent : AppColors.textSecondary,
      ),
    );
  }
}
