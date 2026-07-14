import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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
        final star = Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: filled ? color : muted,
        );
        if (onRate == null) return Padding(padding: const EdgeInsets.all(2), child: star);
        return IconButton(
          onPressed: () => onRate!(i + 1),
          icon: star,
          padding: const EdgeInsets.all(2),
          constraints: const BoxConstraints(),
          splashRadius: size * 0.7,
        );
      }),
    );
  }
}
