import 'package:flutter/material.dart';

/// RideVela palette — monochrome, in the style of the best ride-hailing apps:
/// pure white / pure black canvases, a tight neutral grey ramp, and the
/// primary action in the "ink" colour (black on light, white on dark).
/// Colour is reserved for meaning: green = done/good, red = danger,
/// blue = links/info, amber = caution.
///
/// The ink tokens ([accent], [accentInk], [onAccent], [accentSoft]…) follow the
/// app's current brightness: black in light mode, white in dark mode. Each app
/// calls [syncBrightness] from its MaterialApp builder, so every screen that
/// uses them flips with the theme instead of drawing black-on-black.
class AppColors {
  AppColors._();

  static bool _dark = false;

  /// Brand palette, chosen at build time: `--dart-define=THEME=turquoise`
  /// for "Samarkand Turquoise"; anything else is the monochrome default.
  static const bool turquoise =
      String.fromEnvironment('THEME') == 'turquoise';

  // Samarkand Turquoise: deep teal-navy ink on light, bright turquoise ink on
  // dark; turquoise highlights (route, selection) in both.
  static const Color _tealInk = Color(0xFF0B3C49);
  static const Color _turquoise = Color(0xFF0FA3A8);
  static const Color _turquoiseBright = Color(0xFF2EC4C6);
  static const Color _onTurquoise = Color(0xFF00181B);

  /// Called once per build from each app's `MaterialApp.builder`.
  static void syncBrightness(Brightness brightness) =>
      _dark = brightness == Brightness.dark;

  // --- Ink (the primary action colour) ---------------------------------------
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);

  /// Primary action / selection / emphasis: black on light, white on dark.
  static Color get accent => inkFor(_dark);
  static Color get accentPressed => turquoise
      ? (_dark ? const Color(0xFF26A9AB) : const Color(0xFF14505F))
      : (_dark ? const Color(0xFFE2E2E2) : const Color(0xFF333333));

  /// The brand highlight: the route line, the selected option's outline, live
  /// states. Turquoise in the turquoise palette; the ink itself in monochrome.
  static Color get highlight => highlightFor(_dark);
  static Color highlightFor(bool dark) => turquoise
      ? (dark ? _turquoiseBright : _turquoise)
      : inkFor(dark);

  /// Same ink for text-bearing surfaces (kept as its own name for clarity).
  static Color get accentInk => inkFor(_dark);
  static Color get accentInkPressed => accentPressed;

  /// Quiet fill for selected rows, chips, highlights.
  static Color get accentSoft => softFor(_dark);
  static const Color accentSoftDark = Color(0xFF282828);

  /// Text/icons drawn on an [accent] fill.
  static Color get onAccent => onInkFor(_dark);

  static Color inkFor(bool dark) => turquoise
      ? (dark ? _turquoiseBright : _tealInk)
      : (dark ? white : black);
  static Color onInkFor(bool dark) => turquoise
      ? (dark ? _onTurquoise : white)
      : (dark ? black : white);
  static Color softFor(bool dark) => turquoise
      ? (dark ? const Color(0xFF0E2E31) : const Color(0xFFE6F6F6))
      : (dark ? accentSoftDark : const Color(0xFFF3F3F3));

  /// Near-black chrome (dark buttons on light surfaces).
  static const Color primary = Color(0xFF000000);
  static const Color primaryElevated = Color(0xFF1F1F1F);

  // --- Surfaces & canvas -----------------------------------------------------
  static const Color surfaceLight = Color(0xFFFFFFFF);
  /// Inputs, chips, inset rows on light.
  static const Color surfaceMutedLight = Color(0xFFF3F3F3);
  static const Color backgroundLight = Color(0xFFFFFFFF);

  static const Color surfaceDark = Color(0xFF141414);
  static const Color surfaceMutedDark = Color(0xFF282828);
  static const Color backgroundDark = Color(0xFF000000);

  // --- Text ------------------------------------------------------------------
  static const Color textPrimaryLight = Color(0xFF000000);
  static const Color textSecondaryLight = Color(0xFF545454);
  /// 4.6:1 on white — the lightest grey that still passes WCAG AA.
  static const Color textTertiaryLight = Color(0xFF757575);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFAFAFAF);
  static const Color textTertiaryDark = Color(0xFF8E8E8E);

  // --- Lines -----------------------------------------------------------------
  static const Color borderLight = Color(0xFFE8E8E8);
  static const Color borderDark = Color(0xFF333333);

  // --- Semantic --------------------------------------------------------------
  static const Color success = Color(0xFF05944F);
  static const Color warning = Color(0xFFC67C00);
  static const Color error = Color(0xFFE11900);
  /// Filled destructive buttons: white text on it passes AA.
  static const Color errorInk = Color(0xFFB21400);
  static const Color errorSoft = Color(0xFFFFEFED);
  static const Color errorSoftDark = Color(0xFF3A1510);
  static const Color info = Color(0xFF276EF1);
  /// Rating stars.
  static const Color star = Color(0xFFFFC043);

  /// Modal scrim behind sheets/dialogs.
  static const Color scrim = Color(0x80000000);
}
