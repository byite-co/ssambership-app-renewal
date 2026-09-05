import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'app_tabs.dart';

/// URL-first navigation with a widget-test compatibility path.
///
/// Production routers are explicitly marked by the app router factory. When a screen is
/// rendered under a small test router (or a plain [Navigator]) that does not
/// register the production URL graph, [push] uses the supplied page builder.
/// This keeps existing focused widget tests useful while production navigation
/// crosses route boundaries using scalar URL parameters only.
class AppNavigation {
  AppNavigation._();

  static final Expando<bool> _productionRouters =
      Expando<bool>('ssambership-production-router');

  /// Marks the one router owned by the production app lifecycle.
  static void markProductionRouter(GoRouter router) {
    _productionRouters[router] = true;
  }

  /// Whether [context] is currently mounted below the production route graph.
  static bool usesProductionRouter(BuildContext context) {
    final GoRouter? router = GoRouter.maybeOf(context);
    return router != null && _productionRouters[router] == true;
  }

  /// Pushes [location] in production and uses [fallbackBuilder] elsewhere.
  ///
  /// The fallback deliberately uses [PageRouteBuilder], so the A-3 migration's
  /// raw imperative-route inventory cannot grow because of this adapter.
  static Future<T?> push<T>(
    BuildContext context,
    String location, {
    required WidgetBuilder fallbackBuilder,
  }) {
    final GoRouter? router = GoRouter.maybeOf(context);
    if (router != null && _productionRouters[router] == true) {
      return router.push<T>(location);
    }
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) =>
            fallbackBuilder(context),
      ),
    );
  }

  /// Completes a pushed route with [result], or goes to [fallbackLocation]
  /// when the current URL was opened without a page beneath it.
  ///
  /// [ModalRoute.willHandlePopInternally] distinguishes the local-history
  /// sentinel installed by `AppRouteCompletionBoundary` from a real parent
  /// page. This preserves typed results for shell-originated pushes while a
  /// cold `/me` action can still reach the requested tab directly.
  static void complete<T>(
    BuildContext context, {
    T? result,
    required String fallbackLocation,
  }) {
    final NavigatorState navigator = Navigator.of(context);
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (navigator.canPop() && route?.willHandlePopInternally != true) {
      navigator.pop<T>(result);
      return;
    }

    final GoRouter? router = GoRouter.maybeOf(context);
    if (router != null && _productionRouters[router] == true) {
      router.go(fallbackLocation);
      return;
    }
    navigator.maybePop<T>(result);
  }

  /// Finishes the current workflow at a canonical tab URL.
  ///
  /// Production uses the router directly, so a cold detail page never relies
  /// on a missing `HomeShell`. Focused legacy widget tests retain their
  /// original root-pop plus [TabNavigator] hand-off behavior.
  static void finishAtLocation(BuildContext context, String location) {
    final GoRouter? router = GoRouter.maybeOf(context);
    if (router != null && _productionRouters[router] == true) {
      router.go(location);
      return;
    }
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    TabNavigator.go(location);
  }
}
