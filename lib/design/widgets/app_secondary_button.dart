import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// A role-colored secondary action, optionally on an inner-glass fill.
///
/// 안쪽은 Material [OutlinedButton] 이다. [filled] 면 유리 안쪽 채움(α0.58) +
/// 남색 링, 아니면 투명 배경의 텍스트 액션. [danger] 는 해지·삭제 같은 위험
/// 보조 액션(위험색 8% 채움 + 위험색 글자 — design-v3 §0 '구독 해지하기').
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.filled = true,
    this.expand = true,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final bool expand;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    final Color accent = danger ? AppColors.danger : roleTheme.color;
    final BorderRadius radius = BorderRadius.circular(AppRadius.button);

    final Widget child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label),
            ],
          );

    final Color background = danger
        ? AppColors.danger.withValues(alpha: 0.08)
        : filled
            ? Colors.white.withValues(alpha: AppGlass.innerFill)
            : Colors.transparent;

    final Widget button = OutlinedButton(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(background),
        foregroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.disabled)
              ? AppColors.textSecondary
              : accent,
        ),
        overlayColor: WidgetStatePropertyAll<Color>(
          accent.withValues(alpha: 0.08),
        ),
        side: WidgetStatePropertyAll<BorderSide>(
          filled && !danger
              ? const BorderSide(color: AppColors.ring)
              : BorderSide.none,
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: radius),
        ),
        minimumSize: const WidgetStatePropertyAll<Size>(
          Size(0, AppSpacing.buttonHeight),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 20),
        ),
        elevation: const WidgetStatePropertyAll<double>(0),
        textStyle: const WidgetStatePropertyAll<TextStyle>(AppTypography.button),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
