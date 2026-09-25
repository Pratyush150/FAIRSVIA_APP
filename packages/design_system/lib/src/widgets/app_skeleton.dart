import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../theme/app_spacing.dart';

/// Airbnb-style skeleton loaders. The trick: wrap the *real* layout shape in
/// [Skeletonizer] so the placeholder always matches the loaded content and can
/// never drift out of sync with a hand-drawn mock.

/// A vertical list of placeholder rows — the default loading state for
/// account/history/list screens.
class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({
    super.key,
    this.rows = 6,
    this.hasLeading = true,
    this.hasTrailing = true,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.shrinkWrap = false,
  });

  final int rows;

  /// True inside another scroll view (a ListView's children): the rows take
  /// their own height instead of expanding to fill.
  final bool shrinkWrap;
  final bool hasLeading;
  final bool hasTrailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      child: ListView.separated(
        padding: padding,
        shrinkWrap: shrinkWrap,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, i) => Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: hasLeading ? const CircleAvatar(radius: 22) : null,
            title: const Text('Placeholder title of a realistic width'),
            subtitle: const Text('Secondary supporting line'),
            trailing: hasTrailing ? const Text(r'$00.00') : null,
          ),
        ),
      ),
    );
  }
}

/// Wraps arbitrary content so it renders as a skeleton while [loading] is true,
/// then fades to the real thing. Use when a screen already has a bespoke layout
/// whose exact shape is the best possible placeholder.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({super.key, required this.loading, required this.child});

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(enabled: loading, child: child);
  }
}
