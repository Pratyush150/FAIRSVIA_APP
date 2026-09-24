import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_elevation.dart';
import '../theme/app_ink.dart';
import '../theme/app_spacing.dart';

/// A rounded surface panel. Borderless by default — content is grouped by
/// space, not boxes. `outlined` adds a hairline (use where a panel must read
/// as separate from the page), `elevated` a soft shadow (panels over a busy
/// background), `selected` the ink ring for pickable options.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.selected = false,
    this.elevated = false,
    this.outlined = false,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool selected;
  final bool elevated;
  final bool outlined;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;
    final radius = BorderRadius.circular(AppSpacing.radius);

    if (InkPaper.on && !selected) return _ruled(context, isDark);

    final decoration = BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: radius,
      border: Border.all(
        color: selected
            ? AppColors.accent
            : (outlined ? border : Colors.transparent),
        width: selected ? 2 : 1,
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

  /// Plan E (THEME=ink): no card. The content sits on the page under a
  /// hairline rule, flush with the text around it, like a section of a
  /// printed page. Selection keeps the ring (it is meaning, not decoration).
  Widget _ruled(BuildContext context, bool isDark) {
    final rule = BorderSide(color: InkPaper.rule(isDark));
    final pad = padding == const EdgeInsets.all(AppSpacing.lg)
        ? const EdgeInsets.symmetric(vertical: AppSpacing.x20)
        : padding;
    // A rule above only: stacked sections then share one line between them
    // instead of doubling up.
    final decoration = BoxDecoration(border: Border(top: rule));
    final content = Padding(padding: pad, child: child);
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
