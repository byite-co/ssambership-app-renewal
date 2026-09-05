import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Role-colored primary action for the v3 design system.
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
    final bool enabled = onPressed != null;
    final Color foreground = enabled ? Colors.white : AppColors.textSecondary;
    final BorderRadius radius = BorderRadius.circular(AppRadius.button);

    final Widget button = Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: enabled
            ? roleTheme.button
            : Colors.white.withValues(alpha: AppGlass.innerFill),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: enabled
              ? BorderSide.none
              : BorderSide(
                  color: AppColors.navy.withValues(
                    alpha: AppGlass.ringAlpha,
                  ),
                ),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: SizedBox(
            height: AppSpacing.buttonHeight,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 20, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: AppTypography.button.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
