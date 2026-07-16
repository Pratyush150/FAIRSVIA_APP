import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
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
    final muted = Theme.of(context).brightness == Brightness.dark
        ? AppColors.borderDark
        : AppColors.borderLight;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final filled = i < value;
        Widget star = Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: filled ? color : muted,
        );
        // A filled star springs in; re-keying on `value` re-triggers the pop
        // each time the rating changes, so tapping cascades the stars.
        if (filled) {
          star = star
              .animate(key: ValueKey('star_${i}_$value'))
              .scaleXY(
                begin: 0.6,
                end: 1,
                duration: AppMotion.normal,
                curve: AppMotion.emphasized,
              );
        }
        if (onRate == null) {
          return Padding(padding: const EdgeInsets.all(2), child: star);
        }
        return IconButton(
          onPressed: () {
            AppHaptics.selection();
            onRate!(i + 1);
          },
          icon: star,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(),
          splashRadius: size * 0.7,
        );
      }),
    );
  }
}
