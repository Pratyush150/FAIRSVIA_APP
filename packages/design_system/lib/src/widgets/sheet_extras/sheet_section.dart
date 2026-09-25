import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_ink.dart';
import '../../theme/app_spacing.dart';

/// A titled block for the lower, pulled-up part of a bottom sheet: a small
/// section label (with an optional leading icon) over a softly filled card.
///
/// Used where a sheet dragged fully up would otherwise end in empty space —
/// the extra sections read as part of the sheet, not as a second screen.
class SheetSection extends StatelessWidget {
  const SheetSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.card = true,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  /// False: the child sits under the label without the filled card (e.g. a
  /// poster carousel that brings its own surface).
  final bool card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final label = Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: theme.colorScheme.onSurface),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: inkSectionLabel(
                context,
                theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label,
        const SizedBox(height: AppSpacing.sm),
        if (card)
          DecoratedBox(
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.surfaceMutedDark
                  : AppColors.surfaceMutedLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: child,
            ),
          )
        else
          child,
      ],
    );
  }
}
