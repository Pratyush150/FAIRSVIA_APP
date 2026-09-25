import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// One tile of a [FeatureGrid].
@immutable
class FeatureItem {
  const FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
}

/// Two-up tiles of product features ("Share your trip", "Start code"): an
/// icon disc, a title and one line under it. Lays out two per row and wraps,
/// so any count works; at large text sizes the tiles grow taller, never wider.
class FeatureGrid extends StatelessWidget {
  const FeatureGrid(this.items, {super.key});

  final List<FeatureItem> items;

  @override
  Widget build(BuildContext context) {
    final rows = <List<FeatureItem>>[
      for (var i = 0; i < items.length; i += 2)
        items.sublist(i, i + 2 > items.length ? items.length : i + 2),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _FeatureTile(row[0])),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: row.length > 1
                      ? _FeatureTile(row[1])
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile(this.item);
  final FeatureItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Material(
      color: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.highlight.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, size: 18, color: AppColors.highlight),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                item.title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(item.subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
