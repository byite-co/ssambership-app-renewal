import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'app_navigation.dart';

/// Gives a directly opened leaf URL a safe in-app completion destination.
///
/// A route reached with [GoRouter.push] already has a page beneath it, so it
/// keeps the normal pop/result contract. A cold deep link has no such page.
/// In that case this boundary adds one local-history entry: app-bar, system,
/// browser and programmatic pops all remove that entry and converge on
/// [fallbackLocation] instead of popping the final Navigator page.
class AppRouteCompletionBoundary extends StatefulWidget {
  const AppRouteCompletionBoundary({
    super.key,
    required this.fallbackLocation,
    required this.child,
  });

  final String fallbackLocation;
  final Widget child;

  @override
  State<AppRouteCompletionBoundary> createState() =>
      _AppRouteCompletionBoundaryState();
}

class _AppRouteCompletionBoundaryState
    extends State<AppRouteCompletionBoundary> {
  LocalHistoryEntry? _coldEntry;
  bool _installScheduled = false;
  bool _disposing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleColdEntry();
  }

  void _scheduleColdEntry() {
    if (_coldEntry != null || _installScheduled) return;
    _installScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _installScheduled = false;
      if (!mounted || _coldEntry != null) return;
      if (!AppNavigation.usesProductionRouter(context)) return;

      final NavigatorState navigator = Navigator.of(context);
      if (navigator.canPop()) return;
      final ModalRoute<Object?>? route = ModalRoute.of(context);
      if (route == null) return;

      final LocalHistoryEntry entry = LocalHistoryEntry(
        onRemove: _onColdEntryRemoved,
      );
      _coldEntry = entry;
      route.addLocalHistoryEntry(entry);
    });
  }

  void _onColdEntryRemoved() {
    _coldEntry = null;
    if (_disposing || !mounted) return;
    final GoRouter? router = GoRouter.maybeOf(context);
    if (router != null && AppNavigation.usesProductionRouter(context)) {
      router.go(widget.fallbackLocation);
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _coldEntry?.remove();
    _coldEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
