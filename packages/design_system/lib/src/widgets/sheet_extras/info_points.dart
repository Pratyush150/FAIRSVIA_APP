import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// One line of an [InfoPoints] list.
@immutable
class InfoPoint {
  const InfoPoint({required this.icon, required this.text, this.title});

  final IconData icon;
  final String? title;
  final String text;
}

/// A short list of icon-led facts ("Price shown before you book", "Final fare
/// follows the distance driven") — for "why this price" style notes.
class InfoPoints extends StatelessWidget {
  const InfoPoints(this.points, {super.key});

  final List<InfoPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, p) in points.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(p.icon, size: 18, color: AppColors.highlight),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (p.title != null)
                          TextSpan(
                            text: '${p.title}  ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        TextSpan(text: p.text),
                      ],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
