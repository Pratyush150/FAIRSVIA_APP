import 'package:flutter/material.dart';
import '../theme/phosphor_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../theme/app_ink.dart';
import '../theme/app_motion.dart';

/// Five-star rating. Read-only when [onRate] is null; tappable otherwise.
/// Replaces the ad-hoc star rows in the rider & driver completed sheets.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.value,
    this.onRate,
    this.size = 40,
    this.color = AppColors.star,
  });

  final int value;
  final ValueChanged<int>? onRate;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // THEME=ink: the empty stars are drawn in the outline token (3.3:1) —
    // hairline grey is too faint for a control at Light weight.
    final muted = InkPaper.on
        ? InkPaper.outline(dark)
        : dark
        ? AppColors.borderDark
        : AppColors.borderLight;
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final filled = i < value;
        Widget star = Icon(
          filled ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
          size: size,
          color: filled ? color : muted,
        );
        // A filled star springs in; re-keying on `value` re-triggers the pop
        // each time the rating changes, so tapping cascades the stars. Under
        // Reduce Motion the fill alone says it.
        if (filled) {
          star = star.motion(
            (w) => w.animate(key: ValueKey('star_${i}_$value')).scaleXY(
                  begin: 0.6,
                  end: 1,
                  duration: AppMotion.slow,
                  curve: AppMotion.enter,
                ),
            fadeWhenReduced: false,
          );
        }
        if (onRate == null) {
          return Padding(padding: const EdgeInsets.all(2), child: star);
        }
        final n = i + 1;
        // A screen reader hears "Rate 4 stars", and which stars are lit;
        // the target is 48 × 48 whatever the star size (Android minimum).
        return Semantics(
          selected: filled,
          child: IconButton(
            tooltip: n == 1 ? 'Rate 1 star' : 'Rate $n stars',
            onPressed: () {
              AppHaptics.selection();
              onRate!(n);
            },
            icon: star,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            splashRadius: size * 0.7,
          ),
        );
      }),
    );
    if (onRate != null) return row;
    // Read-only: one phrase, not five unlabelled star glyphs.
    return Semantics(
      label: 'Rated $value out of 5',
      excludeSemantics: true,
      child: row,
    );
  }
}
