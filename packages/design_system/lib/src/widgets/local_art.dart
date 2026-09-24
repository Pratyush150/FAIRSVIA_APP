import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/app_variant.dart';
import '../theme/phosphor_icons.dart';
import 'kolam.dart';

// Plan D — "Local Colour" illustration set, drawn in code so it stays crisp
// at any density, follows light/dark, and ships no image weight. Marigold
// (LocalColour.marigold) appears only here, in the art: never as text, an
// icon colour or a state. Every piece is decorative (excluded from
// semantics); the words around it carry the meaning.

/// The Pune skyline strip at the head of the "Where to?" sheet: the
/// Shaniwar Wada gate with a saffron flag and a marigold toran, a temple
/// shikhara, trees, an auto-rickshaw, a marigold sun, and a line of kolam
/// dots on the ground.
class LocalCityscape extends StatelessWidget {
  const LocalCityscape({super.key});

  /// The art's design box; it scales to the width it is given.
  static const Size design = Size(360, 84);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: design.width / design.height,
        child: CustomPaint(painter: _CityscapePainter(dark)),
      ),
    );
  }
}

class _Palette {
  _Palette(bool dark)
      : stone = dark ? const Color(0xFF3B342B) : const Color(0xFFF1E4CC),
        stoneShade = dark ? const Color(0xFF312B23) : const Color(0xFFE6D2AE),
        line = LocalColour.lineFor(dark),
        door = dark ? const Color(0xFF123E3D) : const Color(0xFF0A5A5A),
        leafFill = dark ? const Color(0xFF24413A) : const Color(0xFFCFE3D6),
        leafShade = dark ? const Color(0xFF1C352F) : const Color(0xFFB7D5C3),
        ground = dark ? const Color(0xFF4A4238) : const Color(0xFFD9C8AA),
        dot = dark ? const Color(0xFF7FD9D6) : const Color(0xFF0A6E6E);

  final Color stone, stoneShade, line, door, leafFill, leafShade, ground, dot;
}

class _CityscapePainter extends CustomPainter {
  _CityscapePainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / LocalCityscape.design.width;
    canvas.save();
    canvas.scale(k);
    final p = _Palette(dark);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = p.line;
    Paint fill(Color c) => Paint()..color = c;
    const groundY = 72.0;

    // Sun: a marigold disc with a paler core, low behind the skyline.
    canvas.drawCircle(const Offset(262, 34), 17,
        fill(LocalColour.marigold.withValues(alpha: dark ? 0.85 : 0.9)));
    canvas.drawCircle(const Offset(262, 34), 11,
        fill(LocalColour.marigoldLight.withValues(alpha: dark ? 0.55 : 0.7)));

    // Two birds.
    for (final (x, y, s) in [(296.0, 20.0, 1.0), (308.0, 27.0, 0.8)]) {
      canvas.drawPath(
          Path()
            ..moveTo(x - 5 * s, y)
            ..quadraticBezierTo(x - 2.5 * s, y - 3 * s, x, y + 0.5)
            ..quadraticBezierTo(x + 2.5 * s, y - 3 * s, x + 5 * s, y),
          line..strokeWidth = 1.1);
    }
    line.strokeWidth = 1.3;

    // Far-left: low wada roofs.
    for (final (x, w, h) in [(10.0, 30.0, 14.0), (34.0, 22.0, 20.0)]) {
      final r = Rect.fromLTWH(x, groundY - h, w, h);
      canvas.drawRect(r, fill(p.stoneShade));
      canvas.drawPath(
          Path()
            ..moveTo(x - 2, groundY - h)
            ..lineTo(x + w / 2, groundY - h - 7)
            ..lineTo(x + w + 2, groundY - h)
            ..close(),
          fill(p.stone));
      canvas.drawPath(
          Path()
            ..moveTo(x - 2, groundY - h)
            ..lineTo(x + w / 2, groundY - h - 7)
            ..lineTo(x + w + 2, groundY - h),
          line);
      // A small window.
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x + w / 2 - 3, groundY - h + 4, 6, 7),
              const Radius.circular(3)),
          line);
    }

    // Temple shikhara.
    _shikhara(canvas, p, line, fill, cx: 82, groundY: groundY);

    // Tree between the temple and the gate.
    _tree(canvas, p, line, fill, const Offset(116, groundY), 13);

    // Shaniwar Wada's Dilli Darwaza.
    _gate(canvas, p, line, fill, cx: 184, groundY: groundY);

    // Tree and auto-rickshaw on the right.
    _tree(canvas, p, line, fill, const Offset(338, groundY), 15);
    _auto(canvas, p, line, fill, x: 280, groundY: groundY);

    // Ground line, then a row of kolam dots under it, fading to the ends.
    canvas.drawLine(const Offset(6, groundY), const Offset(354, groundY),
        Paint()
          ..color = p.ground
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round);
    for (var x = 12.0; x <= 348; x += 12) {
      final edge = math.min(x - 6, 354 - x) / 60;
      canvas.drawCircle(Offset(x, groundY + 6), 1.4,
          fill(p.dot.withValues(alpha: 0.55 * edge.clamp(0.0, 1.0))));
    }
    canvas.restore();
  }

  void _tree(Canvas canvas, _Palette p, Paint line,
      Paint Function(Color) fill, Offset base, double r) {
    final c = base.translate(0, -r - 8);
    canvas.drawLine(base, base.translate(0, -10), line);
    canvas.drawCircle(c.translate(3, 2), r, fill(p.leafShade));
    canvas.drawCircle(c, r, fill(p.leafFill));
    canvas.drawCircle(c, r, line);
  }

  void _shikhara(Canvas canvas, _Palette p, Paint line,
      Paint Function(Color) fill,
      {required double cx, required double groundY}) {
    // Plinth + mandapa.
    final base = Rect.fromLTRB(cx - 18, groundY - 16, cx + 18, groundY);
    canvas.drawRect(base, fill(p.stoneShade));
    canvas.drawRect(base, line);
    // Doorway.
    canvas.drawPath(
        Path()
          ..moveTo(cx - 4, groundY)
          ..lineTo(cx - 4, groundY - 8)
          ..arcToPoint(Offset(cx + 4, groundY - 8),
              radius: const Radius.circular(4))
          ..lineTo(cx + 4, groundY),
        fill(p.door));
    // The curved spire.
    final top = groundY - 52;
    final spire = Path()
      ..moveTo(cx - 14, groundY - 16)
      ..cubicTo(cx - 14, groundY - 34, cx - 8, top + 6, cx - 3, top + 2)
      ..lineTo(cx + 3, top + 2)
      ..cubicTo(cx + 8, top + 6, cx + 14, groundY - 34, cx + 14, groundY - 16)
      ..close();
    canvas.drawPath(spire, fill(p.stone));
    // Shade the right half for volume.
    canvas.save();
    canvas.clipPath(spire);
    canvas.drawRect(
        Rect.fromLTRB(cx + 2, top, cx + 16, groundY), fill(p.stoneShade));
    canvas.restore();
    canvas.drawPath(spire, line);
    // Horizontal courses.
    for (var i = 1; i <= 4; i++) {
      final y = groundY - 16 - i * 7.0;
      final t = (y - (groundY - 16)) / (top + 2 - (groundY - 16));
      final half = 14 - 11 * t * t;
      canvas.drawLine(Offset(cx - half + 1, y), Offset(cx + half - 1, y),
          line..strokeWidth = 0.9);
    }
    line.strokeWidth = 1.3;
    // Amalaka + kalash.
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, top), width: 10, height: 4),
        fill(p.stoneShade));
    canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, top), width: 10, height: 4), line);
    canvas.drawCircle(Offset(cx, top - 5), 2.6, fill(LocalColour.marigold));
    // Saffron pennant.
    canvas.drawLine(Offset(cx, top - 7), Offset(cx, top - 20), line);
    canvas.drawPath(
        Path()
          ..moveTo(cx, top - 20)
          ..lineTo(cx + 11, top - 16.5)
          ..lineTo(cx, top - 13)
          ..close(),
        fill(LocalColour.marigoldDeep));
  }

  void _gate(Canvas canvas, _Palette p, Paint line,
      Paint Function(Color) fill,
      {required double cx, required double groundY}) {
    // Curtain wall.
    final wall = Rect.fromLTRB(cx - 64, groundY - 30, cx + 64, groundY);
    canvas.drawRect(wall, fill(p.stone));
    canvas.drawLine(wall.topLeft, wall.topRight, line);
    canvas.drawLine(wall.topLeft, wall.bottomLeft, line);
    canvas.drawLine(wall.topRight, wall.bottomRight, line);
    _merlons(canvas, p, line, fill, wall.left, wall.right, wall.top);

    // Two bastions flanking the gate.
    for (final bx in [cx - 34.0, cx + 34.0]) {
      final b = Rect.fromLTRB(bx - 13, groundY - 44, bx + 13, groundY);
      canvas.drawRect(b, fill(p.stone));
      canvas.drawRect(Rect.fromLTRB(bx + 3, b.top, b.right, b.bottom),
          fill(p.stoneShade));
      canvas.drawRect(b, line);
      canvas.drawLine(Offset(bx + 3, b.top + 4), Offset(bx + 3, b.bottom),
          line..strokeWidth = 0.8);
      line.strokeWidth = 1.3;
      _merlons(canvas, p, line, fill, b.left - 1, b.right + 1, b.top);
      // Arrow slit.
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(bx - 3, b.top + 16), width: 3, height: 8),
              const Radius.circular(1.5)),
          fill(p.door));
    }

    // Gate block between the bastions, taller than the wall.
    final gate = Rect.fromLTRB(cx - 21, groundY - 38, cx + 21, groundY);
    canvas.drawRect(gate, fill(p.stone));
    canvas.drawRect(gate, line);
    _merlons(canvas, p, line, fill, gate.left, gate.right, gate.top);

    // Pointed (Mughal-Maratha) arch door, studded.
    final door = Path()
      ..moveTo(cx - 11, groundY)
      ..lineTo(cx - 11, groundY - 18)
      ..quadraticBezierTo(cx - 10, groundY - 27, cx, groundY - 31)
      ..quadraticBezierTo(cx + 10, groundY - 27, cx + 11, groundY - 18)
      ..lineTo(cx + 11, groundY)
      ..close();
    canvas.drawPath(door, fill(p.door));
    canvas.drawLine(Offset(cx, groundY - 27), Offset(cx, groundY),
        Paint()
          ..color = p.stone.withValues(alpha: 0.35)
          ..strokeWidth = 0.8);
    for (var row = 0; row < 3; row++) {
      for (final dx in [-6.0, -3.0, 3.0, 6.0]) {
        canvas.drawCircle(Offset(cx + dx, groundY - 5 - row * 6.0), 0.9,
            fill(LocalColour.marigold));
      }
    }

    // Marigold toran swagged across the gate's face.
    final swagLeft = Offset(cx - 19, groundY - 34);
    final swagRight = Offset(cx + 19, groundY - 34);
    final swag = Path()
      ..moveTo(swagLeft.dx, swagLeft.dy)
      ..quadraticBezierTo(cx, groundY - 26, swagRight.dx, swagRight.dy);
    canvas.drawPath(
        swag,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = LocalColour.leaf);
    final m = swag.computeMetrics().first;
    for (var i = 0; i <= 8; i++) {
      final pos = m.getTangentForOffset(m.length * i / 8)!.position;
      canvas.drawCircle(pos, 2.1,
          fill(i.isEven ? LocalColour.marigold : LocalColour.marigoldDeep));
    }
    // Two hanging strands at the ends.
    for (final e in [swagLeft, swagRight]) {
      for (var j = 1; j <= 2; j++) {
        canvas.drawCircle(e.translate(0, j * 4.0), 1.8,
            fill(j.isOdd ? LocalColour.marigoldDeep : LocalColour.marigold));
      }
    }

    // The Bhagwa Dhwaj: a saffron swallow-tail flag over the gate.
    final poleTop = Offset(cx, groundY - 62);
    canvas.drawLine(Offset(cx, gate.top - 4), poleTop, line);
    canvas.drawPath(
        Path()
          ..moveTo(poleTop.dx, poleTop.dy)
          ..lineTo(poleTop.dx + 17, poleTop.dy + 3)
          ..lineTo(poleTop.dx + 11, poleTop.dy + 6.5)
          ..lineTo(poleTop.dx + 17, poleTop.dy + 10)
          ..lineTo(poleTop.dx, poleTop.dy + 12)
          ..close(),
        fill(LocalColour.marigoldDeep));
  }

  void _merlons(Canvas canvas, _Palette p, Paint line,
      Paint Function(Color) fill, double l, double r, double top) {
    const w = 4.0, gap = 3.0;
    final n = ((r - l + gap) / (w + gap)).floor();
    final start = l + (r - l - (n * w + (n - 1) * gap)) / 2;
    for (var i = 0; i < n; i++) {
      final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(start + i * (w + gap), top - 4, w, 4),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2));
      canvas.drawRRect(rect, fill(p.stone));
      canvas.drawRRect(rect, line..strokeWidth = 0.9);
    }
    line.strokeWidth = 1.3;
  }

  void _auto(Canvas canvas, _Palette p, Paint line,
      Paint Function(Color) fill,
      {required double x, required double groundY}) {
    // Side view, facing left: the Pune auto — a rounded marigold hood over
    // a teal tub, open passenger side, one wheel up front, one behind.
    final gy = groundY;
    final tub = Path()
      ..moveTo(x + 3, gy - 7)
      ..lineTo(x + 3, gy - 13)
      ..quadraticBezierTo(x + 3, gy - 19, x + 9, gy - 20)
      ..lineTo(x + 15, gy - 20)
      ..lineTo(x + 15, gy - 12)
      ..lineTo(x + 30, gy - 12)
      ..lineTo(x + 30, gy - 20)
      ..lineTo(x + 38, gy - 20)
      ..quadraticBezierTo(x + 41, gy - 20, x + 41, gy - 16)
      ..lineTo(x + 41, gy - 7)
      ..close();
    canvas.drawPath(tub, fill(p.door));
    // The hood: flat roof, rounded back, sloping front to the windscreen.
    final hood = Path()
      ..moveTo(x + 6, gy - 21)
      ..quadraticBezierTo(x + 8, gy - 33, x + 17, gy - 34)
      ..lineTo(x + 36, gy - 34)
      ..quadraticBezierTo(x + 42, gy - 34, x + 42, gy - 28)
      ..lineTo(x + 42, gy - 20)
      ..lineTo(x + 30, gy - 20)
      ..lineTo(x + 30, gy - 28)
      ..lineTo(x + 15, gy - 28)
      ..lineTo(x + 15, gy - 21)
      ..close();
    canvas.drawPath(hood, fill(LocalColour.marigold));
    canvas.drawPath(hood, line..strokeWidth = 1.1);
    line.strokeWidth = 1.3;
    // Windscreen.
    canvas.drawPath(
        Path()
          ..moveTo(x + 8, gy - 21)
          ..quadraticBezierTo(x + 10, gy - 29, x + 14, gy - 29)
          ..lineTo(x + 14, gy - 21)
          ..close(),
        fill(p.stone.withValues(alpha: 0.9)));
    // Driver's handlebar and the seat inside the open side.
    canvas.drawLine(Offset(x + 13, gy - 22), Offset(x + 17, gy - 19),
        line..strokeWidth = 1.1);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(x + 19, gy - 17, x + 29, gy - 13),
            const Radius.circular(2)),
        fill(LocalColour.marigoldDeep));
    line.strokeWidth = 1.3;
    // Headlamp.
    canvas.drawCircle(
        Offset(x + 4.5, gy - 14), 1.5, fill(LocalColour.marigoldLight));
    // Wheels.
    for (final wx in [x + 9.0, x + 34.0]) {
      canvas.drawCircle(Offset(wx, gy - 4.5), 4.5, fill(p.line));
      canvas.drawCircle(Offset(wx, gy - 4.5), 1.7, fill(p.stone));
    }
  }

  @override
  bool shouldRepaint(_CityscapePainter old) => old.dark != dark;
}

/// The completed-ride check for Plan D: a teal check on a marigold flower,
/// ringed by kolam dots, with a small burst of petals and dots. It pops once
/// on arrival; under Reduce Motion it is drawn finished, still.
class LocalDoneArt extends StatefulWidget {
  const LocalDoneArt({super.key, this.size = 104});

  final double size;

  @override
  State<LocalDoneArt> createState() => _LocalDoneArtState();
}

class _LocalDoneArtState extends State<LocalDoneArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: _DonePainter(_c.value, dark),
          ),
        ),
      ),
    );
  }
}

class _DonePainter extends CustomPainter {
  _DonePainter(this.t, this.dark);
  final double t;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final s = size.shortestSide / 104; // design box 104
    final ink = AppColors.inkFor(dark);
    final onInk = AppColors.onInkFor(dark);
    double seg(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
    final pop = Curves.easeOutBack.transform(seg(0, 0.55));
    final burst = Curves.easeOutCubic.transform(seg(0.2, 0.9));

    // Kolam dot ring.
    const ringDots = 20;
    for (var i = 0; i < ringDots; i++) {
      final a = i / ringDots * 2 * math.pi - math.pi / 2;
      final on = seg(0.1 + i / ringDots * 0.5, 0.2 + i / ringDots * 0.5);
      if (on <= 0) continue;
      canvas.drawCircle(
          c + Offset(math.cos(a), math.sin(a)) * 46 * s,
          1.7 * s * on,
          Paint()..color = ink.withValues(alpha: 0.45));
    }

    // Marigold flower: two layers of rounded petals.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(pop);
    void petals(int n, double r, double len, double wid, Color col,
        double turn) {
      for (var i = 0; i < n; i++) {
        final a = i / n * 2 * math.pi + turn;
        canvas.save();
        canvas.rotate(a);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(r * s, 0), width: len * s, height: wid * s),
                Radius.circular(wid * s / 2)),
            Paint()..color = col);
        canvas.restore();
      }
    }

    petals(14, 27, 20, 12, LocalColour.marigoldDeep, 0);
    petals(14, 23, 18, 11, LocalColour.marigold, math.pi / 14);
    petals(14, 19, 12, 8, LocalColour.marigoldLight, 0);
    // The check disc.
    canvas.drawCircle(Offset.zero, 20 * s, Paint()..color = ink);
    final check = Path()
      ..moveTo(-8.5 * s, 0.5 * s)
      ..lineTo(-2.5 * s, 6.5 * s)
      ..lineTo(9 * s, -6 * s);
    final m = check.computeMetrics().first;
    canvas.drawPath(
        m.extractPath(0, m.length * seg(0.35, 0.75)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4 * s
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = onInk);
    canvas.restore();

    // Burst: petals and dots thrown outward.
    if (burst > 0) {
      const bits = [
        (-60.0, 50.0, 0), (-20.0, 52.0, 1), (25.0, 50.0, 0), (70.0, 51.0, 2),
        (115.0, 50.0, 1), (160.0, 52.0, 0), (205.0, 50.0, 2), (250.0, 51.0, 1),
        (295.0, 50.0, 0), (-95.0, 49.0, 2),
      ];
      for (final (deg, r, kind) in bits) {
        final a = deg * math.pi / 180;
        final pos = c + Offset(math.cos(a), math.sin(a)) * (26 + (r - 26) * burst) * s;
        final col = switch (kind) {
          0 => LocalColour.marigold,
          1 => ink.withValues(alpha: 0.8),
          _ => LocalColour.marigoldDeep,
        };
        if (kind == 1) {
          canvas.drawCircle(pos, 1.8 * s, Paint()..color = col);
        } else {
          canvas.save();
          canvas.translate(pos.dx, pos.dy);
          canvas.rotate(a);
          canvas.drawOval(
              Rect.fromCenter(
                  center: Offset.zero, width: 5.5 * s, height: 3.2 * s),
              Paint()..color = col);
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DonePainter old) => old.t != t || old.dark != dark;
}

/// Plan D's signature payment line: one amber strip, "Pay ₹102 to Rahul:
/// cash or UPI", on the arrived and completed sheets of a cash ride. Amber
/// is the payment-instructions colour; the amount is set in Inter.
class PayDriverStrip extends StatelessWidget {
  const PayDriverStrip({
    super.key,
    required this.amount,
    required this.driverName,
  });

  /// Already formatted, e.g. "₹102".
  final String amount;
  final String driverName;

  /// The strip's words, as read by a screen reader.
  static String text(String amount, String driverName) =>
      'Pay $amount to $driverName: cash or UPI';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = LocalColour.payInkFor(dark);
    final base = theme.textTheme.titleSmall?.copyWith(color: ink);
    return Semantics(
      container: true,
      label: text(amount, driverName),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: LocalColour.payFillFor(dark),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: LocalColour.payEdgeFor(dark)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: dark ? 0.16 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                PhosphorIconsFill.cashRupee,
                size: 20,
                color: ink,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text.rich(
                TextSpan(style: base, children: [
                  const TextSpan(text: 'Pay '),
                  TextSpan(
                    text: amount,
                    style: base
                        ?.copyWith(fontWeight: FontWeight.w700)
                        .tabular(),
                  ),
                  TextSpan(text: ' to $driverName'),
                  TextSpan(
                    text: ': cash or UPI',
                    style: base?.copyWith(fontWeight: FontWeight.w400),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A warm chip for Plan D's lists ("4 seats", "Rate card"): surface.2 fill,
/// a hairline warm edge, 13 px medium label. Tappable chips keep a 48 dp
/// target around the drawn 28 dp pill.
class LocalChip extends StatelessWidget {
  const LocalChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final tappable = onTap != null;
    final fg = tappable ? AppColors.inkFor(dark) : theme.colorScheme.onSurface;
    final pill = Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tappable
            ? LocalColour.badgeFor(dark)
            : (dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight),
        borderRadius: BorderRadius.circular(AppSpacing.pill),
        border: Border.all(
          color: tappable
              ? LocalColour.marigold.withValues(alpha: dark ? 0.4 : 0.55)
              : (dark ? AppColors.borderDark : AppColors.borderLight),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: fg, fontSize: 13, height: 1.1)),
        ],
      ),
    );
    if (!tappable) return pill;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Center(widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}

/// Plan D's kolam loader at a size, for places that want the art without
/// [PulseRadar]'s child glyph (e.g. a larger empty state).
class KolamLoader extends StatelessWidget {
  const KolamLoader({super.key, this.size = 64, this.progress = 0.8});
  final double size;
  final double progress;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          painter: KolamRadarPainter(
            progress: progress,
            color: AppColors.accent,
          ),
        ),
      );
}

/// Whether Plan D's art should draw here. Kept as one switch so screens read
/// `if (LocalArt.on) …`.
abstract final class LocalArt {
  static const bool on = AppVariant.local;
}
