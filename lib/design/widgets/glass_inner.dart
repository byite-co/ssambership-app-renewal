import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_spacing.dart';

/// A translucent block for fields and subdivisions inside a panel.
class GlassInner extends StatelessWidget {
  const GlassInner({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.base),
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppRadius.input),
    ),
    this.ringColor,
    this.fillColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? ringColor;

  /// 채움색. null 이면 기본 안쪽 유리(흰색 α0.58). 입력 필드는 [AppColors.inputFill].
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fillColor ?? Colors.white.withValues(alpha: AppGlass.innerFill),
        borderRadius: borderRadius,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color:
              ringColor ?? AppColors.navy.withValues(alpha: AppGlass.ringAlpha),
        ),
      ),
      child: child,
    );
  }
}
