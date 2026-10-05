import 'package:flutter/material.dart';

import 'app_clay3d.dart';

/// FAIRSVIA palette. The shipped build (Plan F "Map Glass" layout) uses the
/// "Samarkand Turquoise" colours (#0B3C49 teal-navy ink / #0FA3A8 turquoise /
/// #2EC4C6 bright turquoise; owner's choice 2026-10-05, replacing the earlier
/// Ocean Blue). The history below is the inherited "Samarkand Turquoise": the calm white / black canvases
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
  /// The shipped look is **Plan F "Map Glass"** (owner's final pick,
  /// 2026-09-25): a build with no THEME flag is Glass. `THEME=turquoise`
  /// builds the previous default; the other flags remain for comparison.
  static const String _themeFlag = String.fromEnvironment('THEME');
  static const String variant = _themeFlag == '' ? 'glass' : _themeFlag;
  static const bool turquoise = variant != 'mono';

  /// Plan A's dark tokens (midnight, and daynight's night side).
  static const bool planDark = variant == 'midnight' || variant == 'daynight';

  /// Plan B's light tokens (daylight, and daynight's day side).
  static const bool planLight = variant == 'daylight' || variant == 'daynight';

  /// Any of the v2 plans (A/B/C) rather than the original palettes.
  /// The later option builds (docs/plans/colour-palette-options.md and
  /// visual-direction-v3-research.md): five palettes and Plans D/E/F as
  /// solid-token builds. Same layout; tokens only.
  static const bool v3 = variant == 'indigo' ||
      variant == 'lapis' ||
      variant == 'marigold' ||
      variant == 'copper' ||
      variant == 'garnet' ||
      variant == 'local' ||
      variant == 'ink' ||
      variant == 'glass' ||
      variant == 'clay3d';

  /// Any of the v2/v3 option builds rather than the original palettes.
  static const bool v2 = planDark || planLight || v3;

  /// Plan F "Map Glass" (`THEME=glass`): besides its tokens, this build turns
  /// the floating map chrome into frosted glass (see [AppGlass]).
  static const bool glass = variant == 'glass';

  /// Plan G "3D Clay" (`THEME=clay3d`): warm soft-white page, deep teal
  /// #0B7A7B for anything you tap (5.1:1 with white; the brand teal #1FA7A8
  /// is only 2.9:1, so it is the route/selection/art highlight), and every
  /// icon a Blender-rendered 3D picture (the Phosphor3D colour font, see
  /// phosphor_icons.dart and [AppClay3D]).
  static const bool clay3d = variant == 'clay3d';

  // Samarkand Turquoise: deep teal-navy ink on light, bright turquoise ink on
  // dark; turquoise highlights (route, selection) in both.
  //
  // Plan B's light ink is deep teal #0A7C7C (~5:1 with white) and its light
  // highlight the bright #2BC4C4; Plan A's dark ink is #2BC4C4 with #0E0F11
  // text on it.
  static const Color _tealInk =
      variant == 'indigo'
      ? Color(0xFF4B32C3)
      : variant == 'lapis'
      ? Color(0xFF1D3F9E)
      : variant == 'marigold'
      ? Color(0xFFB8430A)
      : variant == 'copper'
      ? Color(0xFF1F2023)
      : variant == 'garnet'
      ? Color(0xFF9B1B45)
      : variant == 'local'
      ? Color(0xFF0A6E6E)
      : variant == 'ink'
      ? Color(0xFF0B0B0C)
      : variant == 'glass'
      ? Color(0xFF0B3C49)
      : variant == 'clay3d'
      ? Color(0xFF0B7A7B)
      : planLight ? Color(0xFF0A7C7C) : Color(0xFF0B3C49);
  static const Color _turquoise =
      variant == 'indigo'
      ? Color(0xFF6A4DF0)
      : variant == 'lapis'
      ? Color(0xFF2F5BD3)
      : variant == 'marigold'
      ? Color(0xFFD9570F)
      : variant == 'copper'
      ? Color(0xFFB4541E)
      : variant == 'garnet'
      ? Color(0xFFC2255C)
      : variant == 'local'
      ? Color(0xFF0A6E6E)
      : variant == 'ink'
      ? Color(0xFF0A7C7C)
      : variant == 'glass'
      ? Color(0xFF0FA3A8)
      : variant == 'clay3d'
      ? Color(0xFF1FA7A8)
      : planLight ? Color(0xFF2BC4C4) : Color(0xFF0FA3A8);
  static const Color _turquoiseBright =
      variant == 'indigo'
      ? Color(0xFFB6A8FF)
      : variant == 'lapis'
      ? Color(0xFFF0C052)
      : variant == 'marigold'
      ? Color(0xFFFFB547)
      : variant == 'copper'
      ? Color(0xFFF09A5E)
      : variant == 'garnet'
      ? Color(0xFFFF7AA0)
      : variant == 'local'
      ? Color(0xFF3CCFCF)
      : variant == 'ink'
      ? Color(0xFF3FC9C9)
      : variant == 'glass'
      ? Color(0xFF2EC4C6)
      : variant == 'clay3d'
      ? Color(0xFF4FD6D2)
      : planDark ? Color(0xFF2BC4C4) : Color(0xFF2EC4C6);
  static const Color _onTurquoise =
      variant == 'indigo'
      ? Color(0xFF120E2A)
      : variant == 'lapis'
      ? Color(0xFF0B0F1A)
      : variant == 'marigold'
      ? Color(0xFF1A0E00)
      : variant == 'copper'
      ? Color(0xFF1B0D04)
      : variant == 'garnet'
      ? Color(0xFF2A0512)
      : variant == 'local'
      ? Color(0xFF0E0F11)
      : variant == 'ink'
      ? Color(0xFF0A0A0A)
      : variant == 'glass'
      ? Color(0xFF0E1114)
      : variant == 'clay3d'
      ? Color(0xFF0E1011)
      : planDark ? Color(0xFF0E0F11) : Color(0xFF00181B);

  /// Dark-mode ink (buttons). Same as the dark highlight except where a
  /// palette separates them (lapis: blue buttons, gold route).
  static const Color _inkDark = variant == 'indigo'
      ? Color(0xFFA898FF)
      : variant == 'lapis'
      ? Color(0xFF8EA8FF)
      : variant == 'marigold'
      ? Color(0xFFFF9F43)
      : variant == 'copper'
      ? Color(0xFFE8894F)
      : variant == 'garnet'
      ? Color(0xFFFF6B94)
      : variant == 'local'
      ? Color(0xFF3CCFCF)
      : variant == 'ink'
      ? Color(0xFFF4F3EE)
      : variant == 'glass'
      ? Color(0xFF2EC4C6)
      : variant == 'clay3d'
      ? Color(0xFF3CC6C6)
      : _turquoiseBright;

  /// Called once per build from each app's `MaterialApp.builder`.
  /// Under THEME=clay3d it also swaps in the dark 3D icon set when the app
  /// turns dark (AppClay3D.useIconSetFor).
  static void syncBrightness(Brightness brightness) {
    _dark = brightness == Brightness.dark;
    if (clay3d) AppClay3D.useIconSetFor(brightness);
  }

  // --- Ink (the primary action colour) ---------------------------------------
  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);

  /// Primary action / selection / emphasis: black on light, white on dark.
  static Color get accent => inkFor(_dark);
  static Color get accentPressed => v3
      // The option palettes: the ink, 18 % toward black (light) / white (dark).
      ? Color.lerp(inkFor(_dark), _dark ? white : black, 0.18)!
      : turquoise
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

  /// Brand-coloured *text* (and small glyphs next to it). The ink in every
  /// build except Plan F on light glass, where the #007C71 ink over a mid-grey
  /// map pixel seen through 72 % glass drops under 4.5:1, so text takes the
  /// deeper #00665E (6.9:1 on white) while buttons keep the ink.
  static Color get accentText => accentTextFor(_dark);
  static Color accentTextFor(bool dark) =>
      glass && !dark ? const Color(0xFF0B3C49) : inkFor(dark);
  static Color get accentInkPressed => accentPressed;

  /// Quiet fill for selected rows, chips, highlights.
  static Color get accentSoft => softFor(_dark);
  static const Color accentSoftDark =
      variant == 'indigo'
      ? Color(0xFF211E30)
      : variant == 'lapis'
      ? Color(0xFF1C2334)
      : variant == 'marigold'
      ? Color(0xFF25201A)
      : variant == 'copper'
      ? Color(0xFF222225)
      : variant == 'garnet'
      ? Color(0xFF271C20)
      : variant == 'local'
      ? Color(0xFF29241D)
      : variant == 'ink'
      ? Color(0xFF1D1D1B)
      : variant == 'glass'
      ? Color(0xFF1E2328)
      : variant == 'clay3d'
      ? Color(0xFF2A2724)
      : planDark ? Color(0xFF1F2024) : Color(0xFF282828);

  /// Text/icons drawn on an [accent] fill.
  static Color get onAccent => onInkFor(_dark);

  static Color inkFor(bool dark) => turquoise
      ? (dark ? _inkDark : _tealInk)
      : (dark ? white : black);
  static Color onInkFor(bool dark) => turquoise
      ? (dark ? _onTurquoise : white)
      : (dark ? black : white);
  static Color softFor(bool dark) => turquoise
      ? (dark
          ? variant == 'indigo'
      ? const Color(0xFF251F45)
      : variant == 'lapis'
      ? const Color(0xFF1E2A4A)
      : variant == 'marigold'
      ? const Color(0xFF3A2512)
      : variant == 'copper'
      ? const Color(0xFF33221A)
      : variant == 'garnet'
      ? const Color(0xFF3A1622)
      : variant == 'local'
      ? const Color(0xFF173230)
      : variant == 'ink'
      ? const Color(0xFF16302F)
      : variant == 'glass'
      ? const Color(0xFF0E2E31)
      : variant == 'clay3d'
      ? const Color(0xFF143130)
      : (planDark ? const Color(0xFF12302F) : const Color(0xFF0E2E31))
          : variant == 'indigo'
      ? const Color(0xFFEEEAFD)
      : variant == 'lapis'
      ? const Color(0xFFE8EEFB)
      : variant == 'marigold'
      ? const Color(0xFFFDEFE3)
      : variant == 'copper'
      ? const Color(0xFFF8ECE3)
      : variant == 'garnet'
      ? const Color(0xFFFBE9EF)
      : variant == 'local'
      ? const Color(0xFFE3F1EE)
      : variant == 'ink'
      ? const Color(0xFFE6F2F1)
      : variant == 'glass'
      ? const Color(0xFFE6F6F6)
      : variant == 'clay3d'
      ? const Color(0xFFE6F4F3)
      : const Color(0xFFE6F6F6))
      : (dark ? accentSoftDark : const Color(0xFFF3F3F3));

  /// Near-black chrome (dark buttons on light surfaces).
  static const Color primary = Color(0xFF000000);
  static const Color primaryElevated = Color(0xFF1F1F1F);

  // --- Surfaces & canvas -----------------------------------------------------
  // Plan B: white sheets on a #F5F6F7 page; Plan A: #17181B sheets on #0E0F11.
  static const Color surfaceLight = variant == 'indigo'
      ? Color(0xFFFFFFFF)
      : variant == 'lapis'
      ? Color(0xFFFFFFFF)
      : variant == 'marigold'
      ? Color(0xFFFFFFFF)
      : variant == 'copper'
      ? Color(0xFFFFFFFF)
      : variant == 'garnet'
      ? Color(0xFFFFFFFF)
      : variant == 'local'
      ? Color(0xFFFFFFFF)
      : variant == 'ink'
      ? Color(0xFFFFFFFF)
      : variant == 'glass'
      ? Color(0xFFFFFFFF)
      : variant == 'clay3d'
      ? Color(0xFFFFFFFF)
      : Color(0xFFFFFFFF);
  /// Inputs, chips, inset rows on light.
  static const Color surfaceMutedLight =
      variant == 'indigo'
      ? Color(0xFFEFEDF7)
      : variant == 'lapis'
      ? Color(0xFFECEFF5)
      : variant == 'marigold'
      ? Color(0xFFF3EEE6)
      : variant == 'copper'
      ? Color(0xFFEFEDEA)
      : variant == 'garnet'
      ? Color(0xFFF3ECEC)
      : variant == 'local'
      ? Color(0xFFF3EDE2)
      : variant == 'ink'
      ? Color(0xFFF0F0EC)
      : variant == 'glass'
      ? Color(0xFFEEF1F3)
      : variant == 'clay3d'
      ? Color(0xFFF2EEE9)
      : planLight ? Color(0xFFEEF0F2) : Color(0xFFF3F3F3);
  static const Color backgroundLight =
      variant == 'indigo'
      ? Color(0xFFF6F5FB)
      : variant == 'lapis'
      ? Color(0xFFF4F6FA)
      : variant == 'marigold'
      ? Color(0xFFFAF7F2)
      : variant == 'copper'
      ? Color(0xFFF6F5F3)
      : variant == 'garnet'
      ? Color(0xFFFAF6F6)
      : variant == 'local'
      ? Color(0xFFFBF7F0)
      : variant == 'ink'
      ? Color(0xFFFAFAF7)
      : variant == 'glass'
      ? Color(0xFFF7F8F9)
      : variant == 'clay3d'
      ? Color(0xFFFAF8F5)
      : planLight ? Color(0xFFF5F6F7) : Color(0xFFFFFFFF);

  static const Color surfaceDark =
      variant == 'indigo'
      ? Color(0xFF171522)
      : variant == 'lapis'
      ? Color(0xFF141A28)
      : variant == 'marigold'
      ? Color(0xFF1B1612)
      : variant == 'copper'
      ? Color(0xFF18181A)
      : variant == 'garnet'
      ? Color(0xFF1C1417)
      : variant == 'local'
      ? Color(0xFF1E1A15)
      : variant == 'ink'
      ? Color(0xFF141413)
      : variant == 'glass'
      ? Color(0xFF15191D)
      : variant == 'clay3d'
      ? Color(0xFF1E1C1A)
      : planDark ? Color(0xFF17181B) : Color(0xFF141414);
  static const Color surfaceMutedDark =
      variant == 'indigo'
      ? Color(0xFF211E30)
      : variant == 'lapis'
      ? Color(0xFF1C2334)
      : variant == 'marigold'
      ? Color(0xFF25201A)
      : variant == 'copper'
      ? Color(0xFF222225)
      : variant == 'garnet'
      ? Color(0xFF271C20)
      : variant == 'local'
      ? Color(0xFF29241D)
      : variant == 'ink'
      ? Color(0xFF1D1D1B)
      : variant == 'glass'
      ? Color(0xFF1E2328)
      : variant == 'clay3d'
      ? Color(0xFF2A2724)
      : planDark ? Color(0xFF1F2024) : Color(0xFF282828);
  static const Color backgroundDark =
      variant == 'indigo'
      ? Color(0xFF0E0D16)
      : variant == 'lapis'
      ? Color(0xFF0B0F1A)
      : variant == 'marigold'
      ? Color(0xFF110D0A)
      : variant == 'copper'
      ? Color(0xFF0F0F10)
      : variant == 'garnet'
      ? Color(0xFF120C0E)
      : variant == 'local'
      ? Color(0xFF14110D)
      : variant == 'ink'
      ? Color(0xFF0A0A0A)
      : variant == 'glass'
      ? Color(0xFF0E1114)
      : variant == 'clay3d'
      ? Color(0xFF141312)
      : planDark ? Color(0xFF0E0F11) : Color(0xFF000000);

  // --- Text ------------------------------------------------------------------
  static const Color textPrimaryLight =
      variant == 'indigo'
      ? Color(0xFF141225)
      : variant == 'lapis'
      ? Color(0xFF0F1729)
      : variant == 'marigold'
      ? Color(0xFF1A140E)
      : variant == 'copper'
      ? Color(0xFF151412)
      : variant == 'garnet'
      ? Color(0xFF1C1214)
      : variant == 'local'
      ? Color(0xFF1C1A17)
      : variant == 'ink'
      ? Color(0xFF0B0B0C)
      : variant == 'glass'
      ? Color(0xFF0F1417)
      : variant == 'clay3d'
      ? Color(0xFF1D1F22)
      : planLight ? Color(0xFF111315) : Color(0xFF000000);
  static const Color textSecondaryLight =
      variant == 'indigo'
      ? Color(0xFF5E5A72)
      : variant == 'lapis'
      ? Color(0xFF556070)
      : variant == 'marigold'
      ? Color(0xFF6B6158)
      : variant == 'copper'
      ? Color(0xFF625E58)
      : variant == 'garnet'
      ? Color(0xFF6A5C5F)
      : variant == 'local'
      ? Color(0xFF5E574D)
      : variant == 'ink'
      ? Color(0xFF55554F)
      : variant == 'glass'
      ? Color(0xFF4A545C)
      : variant == 'clay3d'
      ? Color(0xFF5E6167)
      : planLight ? Color(0xFF5F646B) : Color(0xFF545454);
  /// 4.6:1 on white — the lightest grey that still passes WCAG AA.
  static const Color textTertiaryLight = Color(0xFF757575);
  static const Color textPrimaryDark = variant == 'indigo'
      ? Color(0xFFFFFFFF)
      : variant == 'lapis'
      ? Color(0xFFFFFFFF)
      : variant == 'marigold'
      ? Color(0xFFFFFFFF)
      : variant == 'copper'
      ? Color(0xFFFFFFFF)
      : variant == 'garnet'
      ? Color(0xFFFFFFFF)
      : variant == 'local'
      ? Color(0xFFF6F1E8)
      : variant == 'ink'
      ? Color(0xFFF4F3EE)
      : variant == 'glass'
      ? Color(0xFFF2F5F7)
      : variant == 'clay3d'
      ? Color(0xFFF5F2EE)
      : Color(0xFFFFFFFF);
  static const Color textSecondaryDark =
      variant == 'indigo'
      ? Color(0xFFA9A5BD)
      : variant == 'lapis'
      ? Color(0xFFA3ACBD)
      : variant == 'marigold'
      ? Color(0xFFB0A69B)
      : variant == 'copper'
      ? Color(0xFFA7A5A1)
      : variant == 'garnet'
      ? Color(0xFFB5A5AA)
      : variant == 'local'
      ? Color(0xFFB5AC9E)
      : variant == 'ink'
      ? Color(0xFFA3A29B)
      : variant == 'glass'
      ? Color(0xFFA7B0B8)
      : variant == 'clay3d'
      ? Color(0xFFADA79F)
      : planDark ? Color(0xFFA0A3A8) : Color(0xFFAFAFAF);
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
      variant == 'indigo'
      ? Color(0xFFE1DEEE)
      : variant == 'lapis'
      ? Color(0xFFDDE2EB)
      : variant == 'marigold'
      ? Color(0xFFE8E1D6)
      : variant == 'copper'
      ? Color(0xFFE3E0DB)
      : variant == 'garnet'
      ? Color(0xFFE8DEDF)
      : variant == 'local'
      ? Color(0xFFE6DDCD)
      : variant == 'ink'
      ? Color(0xFFDAD9D3)
      : variant == 'glass'
      ? Color(0xFFDDE2E6)
      : variant == 'clay3d'
      ? Color(0xFFE8E2DA)
      : planLight ? Color(0xFFE3E5E8) : Color(0xFFE8E8E8);
  static const Color borderDark =
      variant == 'indigo'
      ? Color(0xFF2E2A42)
      : variant == 'lapis'
      ? Color(0xFF2A3246)
      : variant == 'marigold'
      ? Color(0xFF352D25)
      : variant == 'copper'
      ? Color(0xFF2F2F33)
      : variant == 'garnet'
      ? Color(0xFF3A2A2F)
      : variant == 'local'
      ? Color(0xFF3A332A)
      : variant == 'ink'
      ? Color(0xFF2E2E2B)
      : variant == 'glass'
      ? Color(0xFF2C3238)
      : variant == 'clay3d'
      ? Color(0xFF37332E)
      : planDark ? Color(0xFF2A2C31) : Color(0xFF333333);

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

  /// Caution as TEXT (or an icon standing in for text). [warning] #C67C00 is
  /// only ~3.3:1 on white, below the 4.5:1 AA minimum (audit 2026-09-25 #16),
  /// so light surfaces get a deeper ochre (5.5:1 on white, 4.7:1 on #EDEDED)
  /// and dark ones the bright amber (≥6:1 on every dark sheet). [warning]
  /// stays for fills, rings and tints. Asserted in contrast_test.dart.
  static const Color warningText = Color(0xFF8F5F00);
  static const Color warningTextDark = warningDark;
  static Color warningTextFor(bool dark) => dark ? warningTextDark : warningText;
  static Color warningTextOf(BuildContext context) =>
      warningTextFor(Theme.of(context).brightness == Brightness.dark);

  /// Text and icons ON a [warning] fill (banners): dark ink, 5.4:1. White on
  /// that ochre was 3.2:1.
  static const Color onWarning = Color(0xFF1F1600);

  /// A success banner fill that carries white text at 5.4:1 ([success]
  /// #05944F with white is 3.9:1).
  static const Color successBanner = Color(0xFF037A41);
  /// Rating stars.
  static const Color star = Color(0xFFFFC043);

  /// Modal scrim behind sheets/dialogs.
  static const Color scrim = Color(0x80000000);
}
