import 'package:flutter/material.dart';

/// Type scale on Inter (bundled in this package): a neutral grotesk. Big,
/// bold, tightly-tracked headings; calm 16 px body; medium-weight labels —
/// the hierarchy comes from size and weight, not colour.
class AppTypography {
  AppTypography._();

  /// Package-qualified family name so apps pick it up without re-declaring.
  static const String fontFamily = 'packages/design_system/Inter';

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
      displaySmall: s(32, FontWeight.w700, height: 1.1, spacing: -0.8),
      headlineLarge: s(28, FontWeight.w700, height: 1.14, spacing: -0.6),
      headlineMedium: s(24, FontWeight.w700, height: 1.18, spacing: -0.4),
      headlineSmall: s(20, FontWeight.w700, height: 1.22, spacing: -0.3),
      titleLarge: s(18, FontWeight.w600, height: 1.25, spacing: -0.2),
      titleMedium: s(16, FontWeight.w600, height: 1.3, spacing: -0.1),
      titleSmall: s(14, FontWeight.w600, height: 1.3),
      bodyLarge: s(16, FontWeight.w400, height: 1.45),
      bodyMedium: s(14, FontWeight.w400, color: secondary, height: 1.45),
      bodySmall: s(12, FontWeight.w400, color: secondary, height: 1.4),
      labelLarge: s(16, FontWeight.w500, height: 1.2),
      labelMedium: s(14, FontWeight.w500, height: 1.2),
      labelSmall: s(12, FontWeight.w500, height: 1.2, spacing: 0.1),
    );
  }
}

/// Ergonomic tabular-figures application: `theme.textTheme.titleMedium?.tabular()`.
extension NumericTextStyle on TextStyle {
  /// This style with tabular (monospaced) figures — for fares, ETAs, ratings.
  TextStyle tabular() =>
      copyWith(fontFeatures: AppTypography.tabularFigures);
}
