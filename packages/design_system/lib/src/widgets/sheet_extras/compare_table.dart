import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// One row of a [CompareTable]: a leading label and one cell per column.
@immutable
class CompareRow {
  const CompareRow({
    required this.label,
    required this.cells,
    this.highlighted = false,
    this.leading,
  });

  final String label;
  final List<String> cells;

  /// The row the user has picked (drawn bold, with a marker).
  final bool highlighted;

  /// Optional small art before the label (e.g. a vehicle glyph).
  final Widget? leading;
}

/// A compact side-by-side comparison: a header row of [columns], then one
/// line per option. Each cell is a short value ("4", "3 min", "₹102").
///
/// Built from rows, not a [Table], so a large text size wraps the label
/// instead of pushing the numbers off the edge.
class CompareTable extends StatelessWidget {
  const CompareTable({super.key, required this.columns, required this.rows});

  final List<String> columns;
  final List<CompareRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.brightness == Brightness.dark
          ? AppColors.textSecondaryDark
          : AppColors.textSecondaryLight,
      fontWeight: FontWeight.w600,
    );
    Widget line({
      required Widget label,
      required List<Widget> cells,
    }) => Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 5, child: label),
        for (final c in cells)
          Expanded(
            flex: 3,
            child: Align(alignment: Alignment.centerRight, child: c),
          ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: line(
            label: const SizedBox.shrink(),
            cells: [
              for (final c in columns)
                Text(c, style: muted, textAlign: TextAlign.right),
            ],
          ),
        ),
        for (final r in rows) ...[
          Divider(height: AppSpacing.md, color: theme.dividerColor),
          MergeSemantics(
            child: Semantics(
              selected: r.highlighted,
              label: [
                r.label,
                for (var i = 0; i < r.cells.length && i < columns.length; i++)
                  '${columns[i]} ${r.cells[i]}',
              ].join(', '),
              excludeSemantics: true,
              child: line(
                label: Row(
                  children: [
                    if (r.leading != null) ...[
                      r.leading!,
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Flexible(
                      child: Text(
                        r.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: r.highlighted
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (r.highlighted) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: AppColors.highlight,
                      ),
                    ],
                  ],
                ),
                cells: [
                  for (final c in r.cells)
                    Text(
                      c,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: r.highlighted
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
