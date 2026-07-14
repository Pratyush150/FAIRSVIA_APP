import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_elevation.dart';
import '../theme/app_spacing.dart';

/// A rounded surface panel. `elevated` swaps the hairline border for a soft
/// shadow (use for cards floating over a busy background). `selected` applies
/// the brand ring — handy for pickable options (ride tiers, payment modes).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.selected = false,
    this.elevated = false,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool selected;
  final bool elevated;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final radius = BorderRadius.circular(AppSpacing.radius);

    final decoration = BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: radius,
      border: Border.all(
        color: selected ? AppColors.accent : border,
        width: selected ? 1.8 : 1,
      ),
      boxShadow: elevated && !selected ? AppElevation.sm : null,
    );

    final content = Padding(padding: padding, child: child);

    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: content,
        ),
      ),
    );
  }
}
