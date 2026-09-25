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
    final muted =
        dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rows[i].icon != null) ...[
                  Icon(rows[i].icon, size: 18, color: muted),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(rows[i].label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: muted)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    rows[i].value,
                    textAlign: TextAlign.end,
                    style: (rows[i].emphasis
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.bodyMedium)
                        ?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: rows[i].positive ? AppColors.success : null,
                    ),
                  ),
                ),
              ],
            ),
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
