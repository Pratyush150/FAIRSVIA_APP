import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// One tile in a [RideToolkitGrid]: an icon over a short label.
class RideToolkitAction {
  const RideToolkitAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Draws the icon in the error colour (SOS / emergency).
  final bool danger;
  final Key? key;
}

/// A row of equal square-ish action tiles (safety toolkit, trip shortcuts):
/// up to [perRow] per row, wrapping onto more rows beyond that. Labels wrap
/// to two lines rather than clip, so large text stays readable.
class RideToolkitGrid extends StatelessWidget {
  const RideToolkitGrid({super.key, required this.actions, this.perRow = 4});

  final List<RideToolkitAction> actions;
  final int perRow;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += perRow) {
      final slice = actions.sublist(
          i, i + perRow > actions.length ? actions.length : i + perRow);
      if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.sm));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < perRow; j++) ...[
              if (j > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: j < slice.length
                    ? _ToolkitTile(action: slice[j])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _ToolkitTile extends StatelessWidget {
  const _ToolkitTile({required this.action});

  final RideToolkitAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final a = action;
    return Semantics(
      button: true,
      label: a.label,
      excludeSemantics: true,
      child: Material(
        key: a.key,
        color: dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          onTap: a.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(a.icon,
                      size: 24,
                      color: a.danger
                          ? AppColors.error
                          : theme.colorScheme.onSurface),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    a.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
