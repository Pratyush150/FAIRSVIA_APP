import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// Build-time look switches beyond colour tokens.
///
/// Every flag is `const`, so a build that is not the variant compiles the
/// branch away and renders exactly as before.
abstract final class AppVariant {
  /// Plan D — "Local Colour" (`--dart-define=THEME=local`): warm paper,
  /// deep teal for anything you tap, Anek Latin type, marigold illustration
  /// art, a kolam-dot finding-driver radar, Fill-weight icon badges on a
  /// marigold tint, and the amber "Pay ₹X to (driver)" strip.
  /// See docs/plans/visual-direction-v3-research.md, Plan D.
  static const bool local = AppColors.variant == 'local';
}

/// Plan D's own tokens: the ones that are not in [AppColors] because no other
/// build has them. Contrast figures are WCAG ratios, computed (see
/// test/local_variant_test.dart, which asserts them).
abstract final class LocalColour {
  /// Illustration accent — **art only**, never text, icons or state
  /// (1.9:1 on paper). Market-swappable: one token for the art.
  static const Color marigold = Color(0xFFF2A93B);

  /// Deeper marigold for shading inside the art (petal centres, shadows).
  static const Color marigoldDeep = Color(0xFFD9822B);

  /// Pale marigold petal highlight inside the art.
  static const Color marigoldLight = Color(0xFFFFD58A);

  /// Leaf green for garlands (art only).
  static const Color leaf = Color(0xFF3F7D4E);

  /// Warm paper — the sheet background (bg.base).
  static const Color paperLight = Color(0xFFFBF7F0);
  static const Color paperDark = Color(0xFF1E1A15);
  static Color paperFor(bool dark) => dark ? paperDark : paperLight;

  /// Icon-badge disc: a marigold tint. The teal ink glyph on it is 5.2:1
  /// (light) and the dark ink 7.2:1 (dark), above the 3:1 icon floor and
  /// the 4.5:1 text floor.
  static const Color badgeLight = Color(0xFFFCEBD2);
  static const Color badgeDark = Color(0xFF3A2B16);
  static Color badgeFor(bool dark) => dark ? badgeDark : badgeLight;

  /// The pay-to-driver strip: amber = payment instructions. Ink on fill is
  /// 6.7:1 (light) and 9.0:1 (dark).
  static const Color payFillLight = Color(0xFFFFF0D4);
  static const Color payInkLight = Color(0xFF7A4A00);
  static const Color payEdgeLight = Color(0xFFF2C77E);
  static const Color payFillDark = Color(0xFF3A2A12);
  static const Color payInkDark = Color(0xFFFFC766);
  static const Color payEdgeDark = Color(0xFF6B4B1C);
  static Color payFillFor(bool dark) => dark ? payFillDark : payFillLight;
  static Color payInkFor(bool dark) => dark ? payInkDark : payInkLight;
  static Color payEdgeFor(bool dark) => dark ? payEdgeDark : payEdgeLight;

  /// Line work in the art: the deep teal ink, softened.
  static Color lineFor(bool dark) =>
      dark ? const Color(0xFF7FD9D6) : const Color(0xFF0A5A5A);
}
