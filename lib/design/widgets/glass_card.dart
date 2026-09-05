import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_spacing.dart';

/// A performant content card built from translucent fill, ring, and shadow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.base),
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppRadius.card),
    ),
    this.showHighlight = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool showHighlight;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: AppGlass.panelFill),
            borderRadius: borderRadius,
            boxShadow: const <BoxShadow>[AppGlass.panelShadow],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: AppColors.navy.withValues(alpha: AppGlass.ringAlpha),
            ),
          ),
          child: child,
        ),
        if (showHighlight)
          Positioned(
            top: 0,
            left: AppRadius.card,
            right: AppRadius.card,
            child: IgnorePointer(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.transparent,
                      Colors.white.withValues(
                        alpha: AppGlass.highlightAlpha,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
