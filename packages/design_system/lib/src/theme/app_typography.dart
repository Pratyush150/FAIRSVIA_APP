import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_variant.dart';

/// Type scale on Inter (bundled in this package): a neutral grotesk. The
/// hierarchy comes from size and weight, not colour.
///
/// The audit's scale (docs/plans/ui-10-audit-plan.md 3.2), size/line/weight,
/// mapped onto Material's slots so plain widgets pick it up:
///
/// | Role        | Size/line/weight | Material slots                         |
/// |-------------|------------------|----------------------------------------|
/// | display     | 28/34/700        | displaySmall, headlineLarge            |
/// | title       | 22/28/600        | headlineSmall, titleLarge              |
/// | body.strong | 17/24/600        | titleMedium                            |
/// | body        | 15/22/400        | bodyLarge (primary), bodyMedium (secondary colour) |
/// | caption     | 13/18/400        | bodySmall                              |
/// | plate       | 22/28/700, tabular, +4 % tracking | [AppTypography.plate] |
///
/// Between the steps: headlineMedium 24/30/700 (a large page title) and
/// titleSmall 15/22/600 (body-size emphasis). Labels (button and chip text)
/// keep their own 16 / 14 / 12 medium sizes.
class AppTypography {
  AppTypography._();

  /// Inter, package-qualified: the numbers face in every build (plate,
  /// fares, ETAs — tabular figures, already bundled).
  static const String interFamily = 'packages/design_system/Inter';

  /// Anek Latin (Ek Type, OFL — fonts/AnekLatin-LICENSE.txt): Plan D's UI
  /// and heading face, drawn to sit with Anek Devanagari.
  static const String anekFamily = 'packages/design_system/AnekLatin';

  /// Whether this build sets its UI text in Anek Latin: Plan D
  /// (`THEME=local`) and the shipped FAIRSVIA look (glass, the default build).
  /// FAIRSVIA's rounder Anek face is part of what sets it apart from RideVela,
  /// which shares this codebase and stays on Inter.
  static const bool anekUi = AppVariant.local || AppColors.glass;

  /// The UI face of this build. Package-qualified so apps pick it up without
  /// re-declaring. Anek Latin where [anekUi], Inter elsewhere.
  static const String fontFamily = anekUi ? anekFamily : interFamily;

  /// The face for numbers: Inter in every build, so fares and plates keep
  /// their tabular figures even where [fontFamily] is Anek.
  static const String numericFamily = interFamily;

  /// Tabular (monospaced) figures — every digit takes the same width so
  /// live-updating fares, ETAs, countdowns, and ratings don't jitter as digits
  /// change. Apply to any numeric text: `style.tabular()`.
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  /// A licence plate as the rider reads it at the kerb: 22/28, bold, tabular
  /// figures, tracked out 4 % so "MH 12 AB 1234" separates cleanly. No colour —
  /// give it one from the theme: `AppTypography.plate.copyWith(color: …)`.
  static const TextStyle plate = TextStyle(
    fontFamily: numericFamily,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 22 * 0.04,
    fontFeatures: tabularFigures,
  );

  static TextTheme textTheme(Color primary, Color secondary) {
    // [size]/[line] in logical pixels; Flutter wants the line as a multiple.
    TextStyle s(
      double size,
      double line,
      FontWeight weight, {
      Color? color,
      double spacing = 0,
    }) =>
        TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          fontWeight: weight,
          color: color ?? primary,
          height: line / size,
          letterSpacing: spacing,
        );

    return TextTheme(
      // display
      displaySmall: s(28, 34, FontWeight.w700, spacing: -0.6),
      headlineLarge: s(28, 34, FontWeight.w700, spacing: -0.6),
      headlineMedium: s(24, 30, FontWeight.w700, spacing: -0.4),
      // title
      headlineSmall: s(22, 28, FontWeight.w600, spacing: -0.3),
      titleLarge: s(22, 28, FontWeight.w600, spacing: -0.3),
      // body.strong
      titleMedium: s(17, 24, FontWeight.w600, spacing: -0.1),
      titleSmall: s(15, 22, FontWeight.w600),
      // body
      bodyLarge: s(15, 22, FontWeight.w400),
      bodyMedium: s(15, 22, FontWeight.w400, color: secondary),
      // caption
      bodySmall: s(13, 18, FontWeight.w400, color: secondary),
      labelLarge: s(16, 20, FontWeight.w500),
      labelMedium: s(14, 18, FontWeight.w500),
      labelSmall: s(12, 16, FontWeight.w500, spacing: 0.1),
    );
  }
}

/// Ergonomic tabular-figures application: `theme.textTheme.titleMedium?.tabular()`.
extension NumericTextStyle on TextStyle {
  /// This style with tabular (monospaced) figures — for fares, ETAs, ratings.
  /// Where the UI face is Anek, the figures are set in Inter.
  TextStyle tabular() => AppTypography.anekUi
      ? copyWith(
          fontFamily: AppTypography.numericFamily,
          fontFeatures: AppTypography.tabularFigures,
        )
      : copyWith(fontFeatures: AppTypography.tabularFigures);
}
