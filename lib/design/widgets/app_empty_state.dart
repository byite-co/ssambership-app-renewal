import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_typography.dart';
import 'app_primary_button.dart';

/// Empty state with a required explanation and an optional action.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.description,
    this.title,
    this.actionLabel,
    this.onAction,
  }) : assert(
          (actionLabel == null && onAction == null) ||
              (actionLabel != null && onAction != null),
          'actionLabel and onAction must be supplied together.',
        );

  final IconData icon;
  final String description;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: roleTheme.tint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: roleTheme.color),
            ),
            if (title != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                title!,
                textAlign: TextAlign.center,
                style: AppTypography.section.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: 20),
              AppPrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
