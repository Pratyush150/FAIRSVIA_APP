import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_variant.dart';
import '../theme/phosphor_fill_map.dart';

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
        // Plan D: a warm marigold-tinted disc under the teal ink.
        return (
          AppVariant.local ? LocalColour.badgeFor(dark) : AppColors.softFor(dark),
          AppColors.inkFor(dark),
        );
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
          AppVariant.local
              ? LocalColour.badgeFor(dark)
              : (dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight),
          dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        );
    }
  }

  /// The glyph as drawn: Plan D draws badge glyphs in Phosphor **Fill**
  /// (same code points as Regular), so a badge reads as a solid stamp; every
  /// other build keeps [icon] as given.
  static IconData glyphFor(IconData icon) =>
      AppVariant.local ? phosphorFillTwin(icon) : icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (fill, ink) = colorsFor(tone, dark);
    final badge = AppColors.glass
        ? _glassBadge(fill, ink, dark)
        : Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        // Plan D: a hairline warm ring, like a printed stamp's edge.
        border: AppVariant.local && tone == AppIconBadgeTone.brand
            ? Border.all(
                color: LocalColour.marigold.withValues(alpha: dark ? 0.35 : 0.45))
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(glyphFor(icon), size: iconSize, color: ink),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: badge);
    return Semantics(label: semanticLabel, image: true, child: badge);
  }

  /// Plan F: a glossy glass bead instead of a flat disc — the tone's tint,
  /// lit from the top-left, with a gradient rim (bright top-left, the tone's
  /// ink bottom-right). No backdrop blur: badges sit on glass that is already
  /// blurred, and dozens of blur passes in a list would cost frames.
  Widget _glassBadge(Color fill, Color ink, bool dark) {
    final lit = Color.alphaBlend(
      Colors.white.withValues(alpha: dark ? 0.16 : 0.70),
      fill,
    );
    final deep = Color.alphaBlend(
      ink.withValues(alpha: dark ? 0.10 : 0.06),
      fill,
    );
    return CustomPaint(
      foregroundPainter: _BeadRimPainter(ink: ink, dark: dark),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [lit, fill, deep],
            stops: const [0, 0.55, 1],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.35 : 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: iconSize, color: ink),
      ),
    );
  }
}

/// The glass bead's 1 px rim: white light on the top-left edge fading into
/// the tone's ink on the bottom-right, plus a small specular highlight.
class _BeadRimPainter extends CustomPainter {
  _BeadRimPainter({required this.ink, required this.dark});

  final Color ink;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r - 0.5);
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? 0.45 : 0.95),
            Colors.white.withValues(alpha: dark ? 0.08 : 0.30),
            ink.withValues(alpha: dark ? 0.45 : 0.30),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
    // Specular glint, top-left.
    canvas.drawOval(
      Rect.fromCenter(
        center: c + Offset(-r * 0.36, -r * 0.52),
        width: r * 0.9,
        height: r * 0.34,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: dark ? 0.22 : 0.55),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(
            center: c + Offset(-r * 0.36, -r * 0.52), radius: r * 0.45)),
    );
  }

  @override
  bool shouldRepaint(_BeadRimPainter old) => old.ink != ink || old.dark != dark;
}
