import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// What an [AppIconBadge] means — the only thing that changes its colour
/// (audit 2.1, rule 4: colour by meaning).
enum AppIconBadgeTone {
  /// The default: a brand-tint disc with the brand ink glyph.
  brand,

  /// Safety, destructive or error context (SOS, delete, GPS lost).
  danger,

  /// Done / good (a sent share, a confirmed contact).
  success,

  /// Needs attention but is not an error (surge, a missing contact).
  warning,

  /// No meaning, just a place or a thing (search results, saved places):
  /// a muted disc with the on-surface ink glyph.
  neutral,
}

/// The ONE icon container of the app (audit 2.1, rule 5): a 40 px circle
/// filled with the tone's soft tint, holding a 20 px Phosphor glyph in the
/// tone's ink. Use it wherever an icon sits on a tinted disc or tile —
/// quick-action cards, safety rows, priming reasons, detail rows — instead of
/// hand-rolled `Container(shape: circle)` / rounded squares at other sizes.
///
/// Decorative by default: the row next to it carries the words (rule 6), so
/// the badge is excluded from semantics unless [semanticLabel] is given.
class AppIconBadge extends StatelessWidget {
  const AppIconBadge({
    super.key,
    required this.icon,
    this.tone = AppIconBadgeTone.brand,
    this.semanticLabel,
  });

  /// Shorthand for the danger tone (SOS, delete account, GPS lost).
  const AppIconBadge.danger({
    super.key,
    required this.icon,
    this.semanticLabel,
  }) : tone = AppIconBadgeTone.danger;

  /// Container diameter — one size everywhere.
  static const double size = 40;

  /// Glyph size inside the container.
  static const double iconSize = 20;

  final IconData icon;
  final AppIconBadgeTone tone;
  final String? semanticLabel;

  /// (fill, glyph) for [tone] in the given brightness. Public so a golden /
  /// contrast test can check every pair clears the 3:1 icon floor.
  static (Color, Color) colorsFor(AppIconBadgeTone tone, bool dark) {
    switch (tone) {
      case AppIconBadgeTone.brand:
        return (AppColors.softFor(dark), AppColors.inkFor(dark));
      case AppIconBadgeTone.danger:
        return (
          dark ? AppColors.errorSoftDark : AppColors.errorSoft,
          dark ? AppColors.dangerDark : AppColors.errorInk,
        );
      case AppIconBadgeTone.success:
        return (
          AppColors.success.withValues(alpha: dark ? 0.22 : 0.12),
          dark ? const Color(0xFF3DD68C) : AppColors.success,
        );
      case AppIconBadgeTone.warning:
        return (
          AppColors.warningFor(dark).withValues(alpha: dark ? 0.2 : 0.12),
          dark ? AppColors.warningDark : const Color(0xFF9A5F00),
        );
      case AppIconBadgeTone.neutral:
        return (
          dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight,
          dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (fill, ink) = colorsFor(tone, dark);
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: ink),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: badge);
    return Semantics(label: semanticLabel, image: true, child: badge);
  }
}
