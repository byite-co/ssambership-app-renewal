import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_spacing.dart';

/// A performant content card built from translucent fill, ring, and shadow.
///
/// [onTap] 이 있으면 카드 전체가 눌리는 목록 행이 된다(리플은 카드 모서리 안).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.base),
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppRadius.card),
    ),
    this.showHighlight = true,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool showHighlight;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final Widget card = _surface();
    if (onTap == null && onLongPress == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: borderRadius,
        child: card,
      ),
    );
  }

  Widget _surface() {
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: double.infinity,
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
