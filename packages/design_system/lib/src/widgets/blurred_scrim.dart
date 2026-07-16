import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// A frosted-glass scrim: a blurred, dimmed backdrop that lifts a modal surface
/// (driver offer, safety sheet) off the map instead of a flat black wash. The
/// blur animates in with the overlay so the transition feels like depth, not a
/// hard cut.
class BlurredScrim extends StatelessWidget {
  const BlurredScrim({
    super.key,
    this.sigma = 7,
    this.color,
    this.onTap,
  });

  final double sigma;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: AppMotion.normal,
          curve: AppMotion.standard,
          builder: (context, t, _) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigma * t, sigmaY: sigma * t),
            child: Container(
              color: (color ?? AppColors.scrim).withValues(
                alpha: ((color ?? AppColors.scrim).a) * t,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
