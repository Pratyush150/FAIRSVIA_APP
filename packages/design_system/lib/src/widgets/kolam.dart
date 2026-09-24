import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_variant.dart';

/// Plan D's "rangoli-dot loader": a kolam pulli (dot) grid that builds up
/// from the centre, ring by ring, and is then wrapped by a looping line —
/// the way a kolam is drawn on a doorstep at dawn.
///
/// The geometry is pure and unit-free (a dot grid of spacing 1), so the sheet
/// radar ([KolamRadarPainter]) and the map pickup ([AppMap]'s kolam circles)
/// share one pattern and one timing.
abstract final class Kolam {
  /// The largest ring: a 1-3-5-7-5-3-1 diamond of 25 dots.
  static const int rings = 3;

  /// One loop through the pattern.
  static const Duration period = Duration(milliseconds: 2800);

  /// The 25 dots as (x, y) grid offsets from the centre, |x| + |y| ≤ [rings].
  static final List<Offset> dots = [
    for (var y = -rings; y <= rings; y++)
      for (var x = -rings; x <= rings; x++)
        if (x.abs() + y.abs() <= rings) Offset(x.toDouble(), y.toDouble()),
  ];

  /// A dot's ring: its grid (Manhattan) distance from the centre.
  static int ringOf(Offset d) => (d.dx.abs() + d.dy.abs()).round();

  static double _ease(double t) => Curves.easeOutBack.transform(t.clamp(0, 1));

  /// How far ring [ring] has "popped" in at loop time [t] (0..1): 0 hidden,
  /// 1 fully drawn (it overshoots slightly mid-pop). Rings land one after
  /// another from the centre; everything fades in the last tenth.
  static double dotScale(int ring, double t) {
    final start = 0.04 + ring * 0.13;
    return _ease((t - start) / 0.12);
  }

  /// The whole pattern's opacity at [t]: full, then a fade before the loop
  /// starts over.
  static double fade(double t) => t < 0.88 ? 1.0 : (1 - (t - 0.88) / 0.12);

  /// How much of the looping line is drawn at [t] (0..1).
  static double lineProgress(double t) =>
      Curves.easeInOut.transform(((t - 0.46) / 0.36).clamp(0.0, 1.0));

  /// The kolam line in grid units around the centre: a closed curve that
  /// passes between the second and third rings and throws a petal loop
  /// round each of the 12 outer dots — never through a dot, as in a real
  /// kolam.
  static Path linePath(double unit, Offset centre) {
    final outer = [
      for (final d in dots)
        if (ringOf(d) == rings) d,
    ]..sort((a, b) =>
        math.atan2(a.dy, a.dx).compareTo(math.atan2(b.dy, b.dx)));
    final n = outer.length;
    Offset p(Offset g) => centre + g * unit;
    // Waist points: between two neighbouring outer dots, pulled in towards
    // the centre so the line slips between rings 2 and 3.
    Offset waist(int i) {
      final a = outer[i], b = outer[(i + 1) % n];
      final mid = (a + b) / 2;
      return mid * ((rings - 0.62) / (mid.dx.abs() + mid.dy.abs()));
    }

    final path = Path()..moveTo(p(waist(n - 1)).dx, p(waist(n - 1)).dy);
    for (var i = 0; i < n; i++) {
      final dot = outer[i];
      final from = waist((i - 1 + n) % n), to = waist(i);
      final out = dot / dot.distance; // outward unit vector
      final tangent = Offset(-out.dy, out.dx);
      // Two controls beyond the dot, splayed along the tangent, draw a
      // rounded petal that wraps it.
      final tip = dot + out * 0.78;
      final c1 = tip - tangent * 0.62;
      final c2 = tip + tangent * 0.62;
      // Order the controls so the curve leaves [from] towards its side.
      final fromSide = ((from - dot).dx * tangent.dx +
                  (from - dot).dy * tangent.dy) <
              0
          ? c1
          : c2;
      final toSide = identical(fromSide, c1) ? c2 : c1;
      path.cubicTo(p(fromSide).dx, p(fromSide).dy, p(toSide).dx, p(toSide).dy,
          p(to).dx, p(to).dy);
    }
    return path..close();
  }
}

/// Paints the kolam loader at loop time [progress] (0..1). With [still] it
/// paints the finished pattern (Reduce Motion: no build-up, no fade).
class KolamRadarPainter extends CustomPainter {
  KolamRadarPainter({
    required this.progress,
    required this.color,
    this.still = false,
    this.hollowCentre = false,
    this.lineColor,
  });

  final double progress;

  /// The dots' colour (the brand ink).
  final Color color;

  /// The looping line's colour; marigold by default (illustration accent).
  final Color? lineColor;
  final bool still;

  /// Leave the inner rings empty for a glyph drawn at the centre.
  final bool hollowCentre;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    // Leave room for the petals past the outer ring.
    final unit = size.shortestSide / 2 / (Kolam.rings + 0.95);
    final t = still ? 0.8 : progress;
    final fade = still ? 1.0 : Kolam.fade(t);
    if (fade <= 0) return;

    // The line first, so the dots sit on top of it.
    final line = lineColor ?? LocalColour.marigold;
    final lp = still ? 1.0 : Kolam.lineProgress(t);
    if (lp > 0) {
      final full = Kolam.linePath(unit, centre);
      final drawn = Path();
      for (final m in full.computeMetrics()) {
        drawn.addPath(m.extractPath(0, m.length * lp), Offset.zero);
      }
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, unit * 0.2)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = line.withValues(alpha: fade),
      );
    }

    final dotR = math.max(1.6, unit * 0.2);
    for (final d in Kolam.dots) {
      final ring = Kolam.ringOf(d);
      if (hollowCentre && ring <= 1) continue;
      final s = still ? 1.0 : Kolam.dotScale(ring, t);
      if (s <= 0) continue;
      // Outer rings slightly lighter, so the pattern reads from the centre.
      final a = (1.0 - ring * 0.12) * fade;
      canvas.drawCircle(
        centre + d * unit,
        dotR * s,
        Paint()..color = color.withValues(alpha: a.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(KolamRadarPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.still != still ||
      old.hollowCentre != hollowCentre ||
      old.lineColor != lineColor;
}
