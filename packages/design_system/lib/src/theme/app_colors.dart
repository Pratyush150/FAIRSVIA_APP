import 'package:flutter/material.dart';

/// RideVela palette — "Samarkand Turquoise": the calm white / black canvases
/// and tight grey ramp of the best ride-hailing apps, with the primary action
/// in the brand "ink" (deep teal-navy on light, turquoise on dark) and
/// turquoise highlights for the route and selection.
/// Colour is reserved for meaning: green = done/good, red = danger,
/// blue = links/info, amber = caution.
///
/// The ink tokens ([accent], [accentInk], [onAccent], [accentSoft]…) follow the
/// app's current brightness: teal-navy in light mode, turquoise in dark mode. Each app
/// calls [syncBrightness] from its MaterialApp builder, so every screen that
/// uses them flips with the theme instead of drawing black-on-black.
class AppColors {
  AppColors._();

  static bool _dark = false;

  /// The build's look, chosen with `--dart-define=THEME=`:
  /// - (unset) / `turquoise`: "Samarkand Turquoise", the owner's pick of
  ///   2026-09-23;
  /// - `mono`: plain black and white;
  /// - `midnight`: Visual Direction v2 Plan A (dark-first, #0E0F11 canvas);
  /// - `daylight`: Plan B (light-first, #F5F6F7 canvas, deep teal #0A7C7C);
  /// - `daynight`: Plan C (B by day, A by night, following the phone).
  /// Build-time, so every token stays `const` and variants cost nothing at
  /// run time. See docs/plans/visual-direction-v2.md.
  static const String variant = String.fromEnvironment('THEME');
  static const bool turquoise = variant != 'mono';

  /// Plan A's dark tokens (midnight, and daynight's night side).
  static const bool planDark = variant == 'midnight' || variant == 'daynight';

  /// Plan B's light tokens (daylight, and daynight's day side).
  static const bool planLight = variant == 'daylight' || variant == 'daynight';

  /// Any of the v2 plans (A/B/C) rather than the original palettes.
  static const bool v2 = planDark || planLight;

  // Samarkand Turquoise: deep teal-navy ink on light, bright turquoise ink on
  // dark; turquoise highlights (route, selection) in both.
  //
  // Plan B's light ink is deep teal #0A7C7C (~5:1 with white) and its light
  // highlight the bright #2BC4C4; Plan A's dark ink is #2BC4C4 with #0E0F11
  // text on it.
  static const Color _tealInk =
      planLight ? Color(0xFF0A7C7C) : Color(0xFF0B3C49);
  static const Color _turquoise =
      planLight ? Color(0xFF2BC4C4) : Color(0xFF0FA3A8);
  static const Color _turquoiseBright =
      planDark ? Color(0xFF2BC4C4) : Color(0xFF2EC4C6);
  static const Color _onTurquoise =
      planDark ? Color(0xFF0E0F11) : Color(0xFF00181B);

  /// Called once per build from each app's `MaterialApp.builder`.
  static void syncBrightness(Brightness brightness) =>
      _dark = brightness == Brightness.dark;

  // --- Ink (the primary action colour) ---------------------------------------
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);

  /// Primary action / selection / emphasis: black on light, white on dark.
  static Color get accent => inkFor(_dark);
  static Color get accentPressed => turquoise
      ? (_dark
          ? const Color(0xFF26A9AB)
          : (planLight ? const Color(0xFF086464) : const Color(0xFF14505F)))
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
  static const Color accentSoftDark =
      planDark ? Color(0xFF1F2024) : Color(0xFF282828);

  /// Text/icons drawn on an [accent] fill.
  static Color get onAccent => onInkFor(_dark);

  static Color inkFor(bool dark) => turquoise
      ? (dark ? _turquoiseBright : _tealInk)
      : (dark ? white : black);
  static Color onInkFor(bool dark) => turquoise
      ? (dark ? _onTurquoise : white)
      : (dark ? black : white);
  static Color softFor(bool dark) => turquoise
      ? (dark
          ? (planDark ? const Color(0xFF12302F) : const Color(0xFF0E2E31))
          : const Color(0xFFE6F6F6))
      : (dark ? accentSoftDark : const Color(0xFFF3F3F3));

  /// Near-black chrome (dark buttons on light surfaces).
  static const Color primary = Color(0xFF000000);
  static const Color primaryElevated = Color(0xFF1F1F1F);

  // --- Surfaces & canvas -----------------------------------------------------
  // Plan B: white sheets on a #F5F6F7 page; Plan A: #17181B sheets on #0E0F11.
  static const Color surfaceLight = Color(0xFFFFFFFF);
  /// Inputs, chips, inset rows on light.
  static const Color surfaceMutedLight =
      planLight ? Color(0xFFEEF0F2) : Color(0xFFF3F3F3);
  static const Color backgroundLight =
      planLight ? Color(0xFFF5F6F7) : Color(0xFFFFFFFF);

  static const Color surfaceDark =
      planDark ? Color(0xFF17181B) : Color(0xFF141414);
  static const Color surfaceMutedDark =
      planDark ? Color(0xFF1F2024) : Color(0xFF282828);
  static const Color backgroundDark =
      planDark ? Color(0xFF0E0F11) : Color(0xFF000000);

  // --- Text ------------------------------------------------------------------
  static const Color textPrimaryLight =
      planLight ? Color(0xFF111315) : Color(0xFF000000);
  static const Color textSecondaryLight =
      planLight ? Color(0xFF5F646B) : Color(0xFF545454);
  /// 4.6:1 on white — the lightest grey that still passes WCAG AA.
  static const Color textTertiaryLight = Color(0xFF757575);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark =
      planDark ? Color(0xFFA0A3A8) : Color(0xFFAFAFAF);
  static const Color textTertiaryDark = Color(0xFF8E8E8E);

  // --- Icons -----------------------------------------------------------------
  /// Neutral (non-semantic) icons: list-row leading glyphs, chevrons, inline
  /// hints. Quieter than body text but above the 3:1 icon-contrast floor on
  /// every surface of its mode (audit 3.1: icon.neutral #9A9DA3 on dark).
  static const Color iconNeutralLight = Color(0xFF6B7078);
  static const Color iconNeutralDark = Color(0xFF9A9DA3);
  static Color iconNeutralFor(bool dark) =>
      dark ? iconNeutralDark : iconNeutralLight;

  // --- Lines -----------------------------------------------------------------
  static const Color borderLight =
      planLight ? Color(0xFFE3E5E8) : Color(0xFFE8E8E8);
  static const Color borderDark =
      planDark ? Color(0xFF2A2C31) : Color(0xFF333333);

  // --- Semantic --------------------------------------------------------------
  static const Color success = Color(0xFF05944F);
  static const Color warning = Color(0xFFC67C00);
  static const Color error = Color(0xFFE11900);
  /// Filled destructive buttons: white text on it passes AA.
  static const Color errorInk = Color(0xFFB21400);
  static const Color errorSoft = Color(0xFFFFEFED);
  static const Color errorSoftDark = Color(0xFF3A1510);
  static const Color info = Color(0xFF276EF1);

  /// Danger and caution tuned for dark surfaces (audit 3.1): the light-mode
  /// [error] #E11900 is only ~4.3:1 on black and [warning] #C67C00 ~6:1 but
  /// muddy, so dark mode gets brighter equivalents. Used by the v2 theme
  /// builds' dark scheme; the shipped turquoise default keeps [error] for now
  /// (its dark screens were tuned with it) — widgets can opt in through
  /// [dangerFor] / [warningFor].
  static const Color dangerDark = Color(0xFFFF4D4F);
  static const Color warningDark = Color(0xFFF5A623);
  static Color dangerFor(bool dark) => dark ? dangerDark : error;
  static Color warningFor(bool dark) => dark ? warningDark : warning;
  /// Rating stars.
  static const Color star = Color(0xFFFFC043);

  /// Modal scrim behind sheets/dialogs.
  static const Color scrim = Color(0x80000000);
}
