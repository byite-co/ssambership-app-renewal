import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Role-colored primary action for the v3 design system.
///
/// 안쪽은 Material [FilledButton] 이다(비활성·포커스·의미론은 Material 규칙).
/// 채움은 역할색 α0.92, 비활성은 유리 안쪽 채움 + 링(design-v3 §0 공통 요소).
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
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

    final Widget button = FilledButton(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.disabled)
              ? Colors.white.withValues(alpha: AppGlass.innerFill)
              : roleTheme.button,
        ),
        foregroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.disabled)
              ? AppColors.textSecondary
              : Colors.white,
        ),
        overlayColor: WidgetStatePropertyAll<Color>(
          Colors.white.withValues(alpha: 0.12),
        ),
        side: WidgetStateProperty.resolveWith<BorderSide?>(
          (Set<WidgetState> states) => states.contains(WidgetState.disabled)
              ? const BorderSide(color: AppColors.ring)
              : null,
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
        // ★ ButtonStyle.textStyle 은 테마 fontFamily 를 상속하지 않는다 — 명시.
        textStyle: const WidgetStatePropertyAll<TextStyle>(AppTypography.button),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: child,
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
