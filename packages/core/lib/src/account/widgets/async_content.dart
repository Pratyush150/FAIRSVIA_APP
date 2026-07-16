import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../../network/api_exception.dart';

/// Loads a future and renders one of four consistent states: loading, error
/// (with retry), empty, or the built content. Shared by every read-only
/// account screen so loading/empty/error UX is uniform and testable.
class AsyncContent<T> extends StatefulWidget {
  const AsyncContent({
    super.key,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.skeleton,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload)
      builder;

  /// Optional predicate to show the empty state instead of [builder].
  final bool Function(T data)? isEmpty;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;

  /// The loading placeholder. Defaults to an Airbnb-style list skeleton; pass a
  /// screen-specific shape when the content isn't a simple list.
  final Widget? skeleton;

  @override
  State<AsyncContent<T>> createState() => _AsyncContentState<T>();
}

class _AsyncContentState<T> extends State<AsyncContent<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _reload() {
    // Block body (not an arrow) so the setState callback returns void — an
    // arrow would return the assigned Future, which setState rejects.
    setState(() {
      _future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        // Cross-fade between states so loading → content never hard-cuts.
        return AnimatedSwitcher(
          duration: AppMotion.normal,
          switchInCurve: AppMotion.standard,
          child: _stateFor(context, snap),
        );
      },
    );
  }

  Widget _stateFor(BuildContext context, AsyncSnapshot<T> snap) {
    if (snap.connectionState == ConnectionState.waiting) {
      // Skeleton placeholder in the shape of the loaded content.
      return KeyedSubtree(
        key: const ValueKey('loading'),
        child: widget.skeleton ?? const AppListSkeleton(),
      );
    }
    if (snap.hasError) {
      return _ErrorState(
        key: const ValueKey('error'),
        message: snap.error is ApiException
            ? (snap.error as ApiException).message
            : 'Something went wrong.',
        onRetry: _reload,
      );
    }
    final data = snap.data as T;
    if (widget.isEmpty?.call(data) ?? false) {
      return _EmptyState(
        key: const ValueKey('empty'),
        icon: widget.emptyIcon,
        title: widget.emptyTitle,
        message: widget.emptyMessage,
      );
    }
    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: () async => _reload(),
      child: widget.builder(context, data, _reload),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });
  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.disabledColor),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
