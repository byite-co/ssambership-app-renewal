import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// 이니셜 아바타 — v3 둥근 사각(반경 16/44px 비율). 사진이 없으면 이름 첫 글자.
/// [tinted] 면 역할 틴트 배경 + 역할색 글자, 아니면 유리 안쪽 채움 + 링 + 본문색.
/// ★ 사진 없을 때 깨진 이미지/카메라 placeholder 를 절대 쓰지 않는다.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.tinted = true,
  });

  final String name;
  final double size;

  /// true: 역할 틴트 배경 / false: 중립(유리 안쪽) 배경.
  final bool tinted;

  String get _initial {
    final String t = name.trim();
    if (t.isEmpty) return '?';
    // 유니코드 안전: 첫 코드포인트 1자.
    return String.fromCharCode(t.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final BorderRadius radius =
        BorderRadius.circular(size * AppRadius.avatar / 44);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tinted
            ? roleTheme.tint
            : Colors.white.withValues(alpha: AppGlass.innerFill),
        borderRadius: radius,
        border: tinted ? null : Border.all(color: AppColors.ring),
      ),
      child: Text(
        _initial,
        style: AppTypography.bodyStrong.copyWith(
          color: tinted ? roleTheme.color : AppColors.textPrimary,
          fontSize: size * 0.4,
          height: 1,
        ),
      ),
    );
  }
}
