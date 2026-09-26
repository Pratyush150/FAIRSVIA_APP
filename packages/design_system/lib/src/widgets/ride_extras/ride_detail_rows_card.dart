import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../app_card.dart';

/// One label/value line in a [RideDetailRowsCard].
class RideDetailRow {
  const RideDetailRow({
    required this.label,
    required this.value,
    this.icon,
    this.emphasis = false,
    this.positive = false,
  });

  final String label;
  final String value;
  final IconData? icon;

  /// Bold value (the total).
  final bool emphasis;

  /// Success-coloured value (a discount).
  final bool positive;
}

/// A card of label/value lines under an optional [title] — the fare and
/// payment summary, trip facts. Values are the caller's real figures; a
/// value that is not known should be left out, not passed as "0".
class RideDetailRowsCard extends StatelessWidget {
  const RideDetailRowsCard({
    super.key,
    this.title,
    required this.rows,
    this.footnote,
  });

  final String? title;
  final List<RideDetailRow> rows;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(title!, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _DetailLine(row: rows[i], muted: muted),
          ],
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(footnote!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// One tidy line: icon · label on the left (never squeezed), the value on
/// the right taking the rest, one line with "…" (two for long values like an
/// address). A tip line (empty value) lets the label use the full width.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.row, required this.muted});

  final RideDetailRow row;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(color: muted);
    final icon = row.icon == null
        ? null
        : Icon(row.icon, size: 18, color: muted);
    if (row.value.isEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[icon, const SizedBox(width: AppSpacing.sm)],
          Expanded(child: Text(row.label, style: labelStyle)),
        ],
      );
    }
    final long = row.value.length > 28;
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: long
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[icon, const SizedBox(width: AppSpacing.sm)],
          // The label keeps its natural width but never more than 45% of the
          // line, so big text sizes can't push the value off the edge.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
            child: Text(
              row.label,
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.end,
              maxLines: long ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style:
                  (row.emphasis
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: row.positive ? AppColors.success : null,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
