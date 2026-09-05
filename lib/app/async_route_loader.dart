import 'package:flutter/material.dart';

import '../shared/errors/friendly_error.dart';
import 'app_scope.dart';
import '../design/widgets/app_blocks.dart';
import '../design/widgets/app_empty_state.dart';
import '../design/widgets/app_page.dart';

typedef AsyncRouteLoad<T> = Future<T?> Function(AppDependencies dependencies);
typedef AsyncRouteDataBuilder<T> = Widget Function(
  BuildContext context,
  T data,
  AppDependencies dependencies,
);

/// Loads an ID-addressed route target before building its existing screen.
///
/// The future is retained for the lifetime of this widget, so parent rebuilds
/// do not refetch the target. A null result deliberately merges "not found"
/// and "not visible under RLS" into the same neutral state.
class AsyncRouteLoader<T> extends StatefulWidget {
  const AsyncRouteLoader({
    super.key,
    required this.load,
    required this.builder,
    this.notFoundMessage = '대상을 찾을 수 없어요.',
    this.errorMessage = '대상을 불러오지 못했어요.',
    this.loadingBuilder,
    this.notFoundBuilder,
    this.errorBuilder,
  });

  final AsyncRouteLoad<T> load;
  final AsyncRouteDataBuilder<T> builder;
  final String notFoundMessage;
  final String errorMessage;
  final WidgetBuilder? loadingBuilder;
  final WidgetBuilder? notFoundBuilder;
  final Widget Function(BuildContext context, Object error, VoidCallback retry)?
      errorBuilder;

  @override
  State<AsyncRouteLoader<T>> createState() => _AsyncRouteLoaderState<T>();
}

class _AsyncRouteLoaderState<T> extends State<AsyncRouteLoader<T>> {
  AppDependencies? _dependencies;
  Future<T?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppDependencies dependencies = AppScope.of(context);
    if (!identical(_dependencies, dependencies)) {
      _dependencies = dependencies;
      _future = _load(dependencies);
    }
  }

  Future<T?> _load(AppDependencies dependencies) =>
      Future<T?>(() => widget.load(dependencies));

  void _retry() {
    final AppDependencies? dependencies = _dependencies;
    if (dependencies == null) return;
    setState(() {
      _future = _load(dependencies);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Future<T?>? future = _future;
    final AppDependencies? dependencies = _dependencies;
    if (future == null || dependencies == null) {
      return (widget.loadingBuilder ?? _defaultLoading)(context);
    }
    return FutureBuilder<T?>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<T?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return (widget.loadingBuilder ?? _defaultLoading)(context);
        }
        if (snapshot.hasError) {
          final Object error = snapshot.error ?? const _UnknownRouteLoadError();
          final errorBuilder = widget.errorBuilder;
          if (errorBuilder != null) {
            return errorBuilder(context, error, _retry);
          }
          return _defaultError(context, error);
        }
        final T? data = snapshot.data;
        if (data == null) {
          return (widget.notFoundBuilder ?? _defaultNotFound)(context);
        }
        return widget.builder(context, data, dependencies);
      },
    );
  }

  Widget _defaultLoading(BuildContext context) => const AppPage(
        title: '',
        body: AppLoadingView(),
      );

  Widget _defaultNotFound(BuildContext context) => AppPage(
        title: '',
        body: AppEmptyState(
          icon: Icons.search_off_rounded,
          title: widget.notFoundMessage,
          description: '삭제됐거나 접근 권한이 없어요.',
        ),
      );

  Widget _defaultError(BuildContext context, Object error) => AppPage(
        title: '',
        body: AppErrorView(
          title: widget.errorMessage,
          message: friendlyError(error),
          onRetry: _retry,
        ),
      );
}

class _UnknownRouteLoadError implements Exception {
  const _UnknownRouteLoadError();
}
