import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_glass.dart';
import '../tokens/app_spacing.dart';

enum GlassSurfacePreset { panel, bar }

/// A blurred glass surface reserved for bars and sheets.
class GlassSurface extends StatelessWidget {
  const GlassSurface.panel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(AppRadius.card),
    ),
  }) : preset = GlassSurfacePreset.panel;

  const GlassSurface.bar({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = BorderRadius.zero,
  }) : preset = GlassSurfacePreset.bar;

  final GlassSurfacePreset preset;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;

  double get fill =>
      preset == GlassSurfacePreset.bar ? AppGlass.barFill : AppGlass.panelFill;

  double get blur =>
      preset == GlassSurfacePreset.bar ? AppGlass.barBlur : AppGlass.panelBlur;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: fill),
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
      ),
    );
  }
}
