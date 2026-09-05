import 'package:flutter/material.dart';

import '../tokens/app_spacing.dart';
import 'glass_inner.dart';

/// Static inner-glass placeholder with a card silhouette.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 92,
    this.radius = AppRadius.card,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: GlassInner(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(radius),
        child: const SizedBox.expand(),
      ),
    );
  }
}
