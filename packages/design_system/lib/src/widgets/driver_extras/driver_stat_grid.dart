import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// One figure on a [DriverStatGrid]: "₹1,240 · Earned today".
class DriverStat {
  const DriverStat({
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
  });

  final String label;
  final String value;
  final IconData icon;

  /// Optional small line under the label ("of 12 h limit").
  final String? caption;
}

/// A two-column grid of figure tiles for the driver's pulled-up sheet
/// (today's earnings, trips, online time …). Rows size to their content, so
/// large text wraps instead of overflowing.
class DriverStatGrid extends StatelessWidget {
  const DriverStatGrid({super.key, required this.stats, this.onTap});

  final List<DriverStat> stats;

  /// Makes every tile a button (e.g. "open the earnings dashboard").
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: AppSpacing.sm));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Tile(stat: stats[i], onTap: onTap)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: i + 1 < stats.length
                  ? _Tile(stat: stats[i + 1], onTap: onTap)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.stat, this.onTap});

  final DriverStat stat;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      button: onTap != null,
      label: '${stat.label}: ${stat.value}'
          '${stat.caption == null ? '' : ', ${stat.caption}'}',
      excludeSemantics: true,
      child: Material(
        color: dark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.accentSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(stat.icon, size: 20, color: AppColors.accentTextFor(dark)),
                const SizedBox(height: AppSpacing.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(stat.value,
                      maxLines: 1,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 2),
                Text(stat.label, style: theme.textTheme.bodySmall),
                if (stat.caption != null)
                  Text(stat.caption!,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
