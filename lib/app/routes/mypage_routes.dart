import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/mypage/data/mypage_models.dart';
import '../../features/mypage/mypage_screen.dart';
import '../../shared/constants/app_constants.dart';
import '../app_route_paths.dart';
import '../app_tabs.dart';

/// My-page routes are added one destination at a time during A-3.
List<RouteBase> buildMyPageRoutes() => <RouteBase>[
      GoRoute(
        path: AppRoutePaths.myPage,
        builder: (BuildContext context, GoRouterState state) =>
            const MyPageRoutePage(),
      ),
    ];

/// Route-level scaffold for [MyPageScreen].
///
/// Tab hand-offs close this pushed route with the destination tab index so the
/// underlying home shell can switch the visible tab after the pop completes.
class MyPageRoutePage extends StatelessWidget {
  const MyPageRoutePage({super.key, this.loaderOverride});

  /// Existing focused widget tests can keep supplying deterministic data.
  final Future<MyPageData> Function()? loaderOverride;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppConstants.myPageTitle)),
      body: MyPageScreen(
        loaderOverride: loaderOverride,
        onOpenQuestionsTab: () =>
            Navigator.of(context).pop(AppTab.questionRoom),
        onOpenNotifications: () =>
            Navigator.of(context).pop(AppTab.notifications),
      ),
    );
  }
}
