import 'package:flutter/material.dart';

import 'tokens/app_colors.dart';
import 'tokens/app_glass.dart';

enum AppRole { student, mentor }

/// Supplies the role accent without coupling the v3 design system to auth.
class RoleTheme extends InheritedWidget {
  const RoleTheme({
    super.key,
    required this.role,
    required super.child,
  });

  final AppRole role;

  Color get color =>
      role == AppRole.student ? RoleColors.student : RoleColors.mentor;

  Color get button => color.withValues(alpha: AppGlass.buttonAlpha);

  Color get tint => color.withValues(alpha: AppGlass.tintAlpha);

  static RoleTheme of(BuildContext context) {
    final RoleTheme? result =
        context.dependOnInheritedWidgetOfExactType<RoleTheme>();
    if (result == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('RoleTheme.of() called without a RoleTheme ancestor.'),
        ErrorDescription(
          'Wrap the v3 design-system subtree in RoleTheme(role: ..., child: ...).',
        ),
      ]);
    }
    return result;
  }

  @override
  bool updateShouldNotify(RoleTheme oldWidget) => role != oldWidget.role;
}
