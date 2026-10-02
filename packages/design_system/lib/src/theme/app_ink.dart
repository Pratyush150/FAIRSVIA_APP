import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Plan E — "Ink & Paper" (`--dart-define=THEME=ink`;
/// docs/plans/visual-direction-v3-research.md, Plan E).
///
/// A printed character rather than a new palette: near-black ink on
/// paper-white, hairline rules instead of cards, line-art icons and vehicles,
/// small-caps section labels and one serif for three big moments. Teal is
/// kept for the route and the current selection only; the primary button is
/// ink.
///
/// Everything here is a build-time constant. Every call site gates on [on],
/// so the default build and the other THEME builds render exactly as before.
abstract final class InkPaper {
  /// True only in the THEME=ink build.
  static const bool on = AppColors.variant == 'ink';

  /// Instrument Serif (OFL). Display only, and only for the three serif
  /// moments: the ride-status headline, the receipt total and the splash
  /// wordmark. One weight; never set below 22 pt.
  static const String serifFamily = 'packages/design_system/InstrumentSerif';

  /// Inter SemiBold drawing lowercase as capitals (tool/ink_caps/build.py):
  /// small-caps labels whose text stays as written, so screen readers and
  /// tests see "Add a tip", not "ADD A TIP".
  static const String capsFamily = 'packages/design_system/FairsviaCaps';

  // --- Tokens (Plan E table) -------------------------------------------------
  /// Decorative 1 px rules only (1.4:1 on white — never the only edge of a
  /// control).
  static const Color ruleLight = Color(0xFFDAD9D3);
  static const Color ruleDark = Color(0xFF2E2E2B);
  static Color rule(bool dark) => dark ? ruleDark : ruleLight;

  /// Meaning-bearing outlines (inputs, outlined chips): 3.3:1 / 3.7:1.
  static const Color outlineLight = Color(0xFF8A8A83);
  static const Color outlineDark = Color(0xFF707069);
  static Color outline(bool dark) => dark ? outlineDark : outlineLight;

  /// The paper the ticket is printed on (bg.base).
  static Color paper(bool dark) =>
      dark ? AppColors.backgroundDark : AppColors.backgroundLight;

  /// Ink for text and line art.
  static Color ink(bool dark) =>
      dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

  /// Teal: the route, the selection mark, links. 5.0:1 on white (L),
  /// 9.1:1 on #141413 (D).
  static Color teal(bool dark) => AppColors.highlightFor(dark);

  // --- Type -----------------------------------------------------------------
  /// Section labels ("Add a tip", "Pickup") in small caps: 12/16 SemiBold,
  /// tracked +1.2, secondary ink (7.2:1 on paper and on white).
  static TextStyle label(bool dark) => TextStyle(
    fontFamily: capsFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
  );

  /// A serif moment at [size] (32 for the status headline, 44 for a total).
  /// Instrument Serif has no ₹ and no tabular figures, so Inter is the
  /// fallback for any glyph it lacks.
  static TextStyle serif(double size, {Color? color}) => TextStyle(
    fontFamily: serifFamily,
    fontFamilyFallback: const [AppTypography.fontFamily],
    fontSize: size,
    height: 1.1,
    fontWeight: FontWeight.w400,
    letterSpacing: size >= 36 ? -0.6 : -0.2,
    color: color,
  );
}

/// Plan E hooks on the shared type scale. Outside THEME=ink every helper
/// returns [base] untouched.
extension InkPaperText on TextStyle {
  /// This style as a serif moment (THEME=ink), else unchanged.
  TextStyle serifMoment(double size) => InkPaper.on
      ? merge(InkPaper.serif(size)).copyWith(fontWeight: FontWeight.w400)
      : this;
}

/// An amount as a serif moment ("₹75"): the figures in Instrument Serif at
/// [size], the currency sign (which the serif lacks, so it falls back to
/// Inter) at 62 % so its heavier sans stroke does not dominate. The text is
/// the same string, so readers and finders see "₹75".
TextSpan inkAmountSpan(String money, {required double size, Color? color}) {
  final i = money.indexOf(RegExp(r'[0-9]'));
  if (i <= 0) {
    return TextSpan(text: money, style: InkPaper.serif(size, color: color));
  }
  return TextSpan(
    children: [
      TextSpan(
        text: money.substring(0, i),
        style: InkPaper.serif(size * 0.62, color: color),
      ),
      TextSpan(
        text: money.substring(i),
        style: InkPaper.serif(size, color: color),
      ),
    ],
  );
}

/// A section label: small caps under THEME=ink, [fallback] everywhere else.
TextStyle? inkSectionLabel(BuildContext context, TextStyle? fallback) {
  if (!InkPaper.on) return fallback;
  return InkPaper.label(Theme.of(context).brightness == Brightness.dark);
}
