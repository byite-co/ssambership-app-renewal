import 'package:flutter/material.dart';

import '../role_theme.dart';
import '../tokens/app_spacing.dart';
import '../tokens/app_typography.dart';

/// Role-tinted v3 badge. The legacy AppBadge remains in app_badge.dart.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final RoleTheme roleTheme = RoleTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: roleTheme.tint,
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: roleTheme.color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
