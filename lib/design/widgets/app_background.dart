import 'package:flutter/material.dart';

import '../tokens/app_colors.dart';

/// The role-neutral v3 page background.
class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: <double>[0, 0.52, 1],
          colors: <Color>[
            AppColors.bgTop,
            AppColors.bgMid,
            AppColors.bgBot,
          ],
        ),
      ),
      child: child,
    );
  }
}
