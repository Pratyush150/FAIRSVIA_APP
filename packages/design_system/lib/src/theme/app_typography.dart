import 'package:flutter/material.dart';

/// Type scale built on Plus Jakarta Sans (bundled in this package) — a
/// geometric-humanist sans in the spirit of premium product UIs. Large headings
/// use bold weights with tight negative tracking; body stays comfortable.
class AppTypography {
  AppTypography._();

  /// Package-qualified family name so apps pick it up without re-declaring.
  static const String fontFamily = 'packages/design_system/PlusJakartaSans';

  /// Tabular (monospaced) figures — every digit takes the same width so
  /// live-updating fares, ETAs, countdowns, and ratings don't jitter as digits
  /// change. Apply to any numeric text: `style.tabular()`.
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  static TextTheme textTheme(Color primary, Color secondary) {
    TextStyle s(
      double size,
      FontWeight weight, {
      Color? color,
      double height = 1.3,
      double spacing = 0,
    }) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          color: color ?? primary,
          height: height,
          letterSpacing: spacing,
        );

    return TextTheme(
      displaySmall: s(32, FontWeight.w800, height: 1.08, spacing: -0.6),
      headlineLarge: s(28, FontWeight.w800, height: 1.12, spacing: -0.5),
      headlineMedium: s(24, FontWeight.w700, height: 1.16, spacing: -0.4),
      headlineSmall: s(20, FontWeight.w700, height: 1.2, spacing: -0.2),
      titleLarge: s(18, FontWeight.w700, height: 1.25, spacing: -0.2),
      titleMedium: s(16, FontWeight.w600, height: 1.3),
      titleSmall: s(14, FontWeight.w600, height: 1.3),
      bodyLarge: s(16, FontWeight.w400, height: 1.45),
      bodyMedium: s(14, FontWeight.w400, color: secondary, height: 1.45),
      bodySmall: s(13, FontWeight.w400, color: secondary, height: 1.4),
      labelLarge: s(15, FontWeight.w600, height: 1.2),
      labelMedium: s(13, FontWeight.w600, height: 1.2),
      labelSmall: s(11, FontWeight.w700, height: 1.2, spacing: 0.4),
    );
  }
}

/// Ergonomic tabular-figures application: `theme.textTheme.titleMedium?.tabular()`.
extension NumericTextStyle on TextStyle {
  /// This style with tabular (monospaced) figures — for fares, ETAs, ratings.
  TextStyle tabular() =>
      copyWith(fontFeatures: AppTypography.tabularFigures);
}
