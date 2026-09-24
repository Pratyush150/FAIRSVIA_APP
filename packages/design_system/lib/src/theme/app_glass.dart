import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// Plan F "Map Glass" tokens (docs/plans/visual-direction-v3-research.md,
/// Plan F): glass = a fill at the given alpha over a background blur.
///
/// Only the `THEME=glass` build draws glass ([enabled]); every other build
/// keeps its solid surfaces, and nothing here is read on their paths.
abstract final class AppGlass {
  /// True in the `THEME=glass` build only. Build-time, so the other builds
  /// compile the glass branches away.
  static const bool enabled = AppColors.glass;

  /// Background blur (σ) behind glass.
  static const double blurSigma = 24;

  /// Floating sheets: inset from the screen edges, and their corner radius.
  static const double sheetInset = 12;
  static const double sheetRadius = 28;

  /// glass.fill — floating pills and map buttons (#FFFFFF @ 72 % /
  /// #12161A @ 70 %).
  static Color fill(bool dark) =>
      dark ? const Color(0xB312161A) : const Color(0xB8FFFFFF);

  /// glass.fill.strong — glass that carries text blocks (#FFFFFF @ 84 % /
  /// #12161A @ 82 %). Keeps secondary text above AA over any map pixel.
  static Color fillStrong(bool dark) =>
      dark ? const Color(0xD112161A) : const Color(0xD6FFFFFF);

  /// glass.rim — the 1 px top-edge highlight (decorative, #FFFFFF @ 60 % /
  /// @ 12 %).
  static Color rim(bool dark) =>
      dark ? const Color(0x1FFFFFFF) : const Color(0x99FFFFFF);

  /// surface.solid — what glass becomes when it must not be translucent.
  static Color solid(bool dark) =>
      dark ? const Color(0xFF15191D) : const Color(0xFFF7F8F9);

  /// Whether glass must draw solid here. Flutter exposes iOS "Increase
  /// Contrast" / Android high-contrast text as [MediaQueryData.highContrast];
  /// it has no Reduce Transparency flag, and low-end-device detection is not
  /// built, so those two fallbacks from the plan are NOT covered.
  static bool solidFallback(BuildContext context) =>
      MediaQuery.maybeHighContrastOf(context) ?? false;
}

/// Plan F's sheet motion: an under-damped spring (M3 Expressive
/// style) — the sheet overshoots its new size by a few pixels and settles,
/// so it reads as one physical object changing shape. Use with
/// [AppMotion.slower]; under Reduce Motion callers pass [Duration.zero].
class GlassSpringCurve extends Curve {
  const GlassSpringCurve();

  static final SpringSimulation _sim = SpringSimulation(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: 0.74),
    0,
    1,
    0,
  );

  /// Seconds of spring time mapped onto the curve's 0–1.
  static const double _span = 0.6;

  @override
  double transformInternal(double t) => _sim.x(t * _span);
}
