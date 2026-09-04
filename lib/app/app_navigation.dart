import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

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
  /// The fallback deliberately uses [PageRouteBuilder], not
  /// `MaterialPageRoute`, so the A-3 migration's raw route count cannot grow.
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
}
