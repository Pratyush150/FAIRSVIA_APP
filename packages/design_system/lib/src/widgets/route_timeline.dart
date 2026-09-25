import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// One stop on a [RouteTimeline]: a small caption ("Pickup", "Drop-off",
/// "Stop 1") over the address.
class RouteTimelineStop {
  const RouteTimelineStop({required this.label, required this.address});

  final String label;
  final String address;
}

/// A trip's route as a vertical timeline: the pickup as a hollow ring, any
/// stops as small dots, the destination as a filled square, joined by a
/// rail. Each stop carries a muted caption over the address, which wraps
/// (never ellipsises) so a long address stays readable at large text.
class RouteTimeline extends StatelessWidget {
  const RouteTimeline({super.key, required this.stops});

  /// First is the pickup, last the destination.
  final List<RouteTimelineStop> stops;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface;
    final muted =
        dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final rail = muted.withValues(alpha: 0.35);

    Widget marker(int i) {
      if (i == 0) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ink, width: 2.5),
          ),
        );
      }
      if (i == stops.length - 1) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: muted, shape: BoxShape.circle),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < stops.length; i++) {
      final last = i == stops.length - 1;
      final s = stops[i];
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 20,
              child: Column(
                children: [
                  // Top of the rail above the marker (hidden on the first).
                  SizedBox(
                    height: 4,
                    child: i == 0
                        ? null
                        : Center(child: Container(width: 2, color: rail)),
                  ),
                  SizedBox(height: 12, child: Center(child: marker(i))),
                  Expanded(
                    child: last
                        ? const SizedBox.shrink()
                        : Center(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.only(top: 3),
                              color: rail,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.lg),
                child: Semantics(
                  label: '${s.label}: ${s.address}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.address,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: last ? FontWeight.w600 : FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}
