import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// The Home's "end of page" moment: a big quiet tagline, a subtitle, and a
/// low-contrast skyline-and-road drawing in brand teal. Muted on purpose —
/// it signs off the page, it does not ask for anything.
class BrandFooter extends StatelessWidget {
  const BrandFooter({
    super.key,
    this.tagline = '#RideVela',
    this.subtitle = 'Rides, the Pune way',
  });

  final String tagline;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = dark
        ? AppColors.textTertiaryDark
        : AppColors.textTertiaryLight;

    return Semantics(
      container: true,
      label: '$tagline. $subtitle',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.huge,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tagline,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.displaySmall?.copyWith(
                fontSize: 40,
                height: 44 / 40,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
                color: muted.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: 96,
              width: double.infinity,
              child: CustomPaint(
                painter: BrandFooterPainter(
                  color: AppColors.highlightFor(dark),
                  dark: dark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A gentle Pune skyline — a hill fort's ridge, low blocks, a temple
/// spire — over a curving road with a dashed centre line, all in [color]
/// at low opacity. Deterministic: the same size paints the same picture.
class BrandFooterPainter extends CustomPainter {
  const BrandFooterPainter({required this.color, required this.dark});

  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    Paint fill(double a) => Paint()..color = color.withValues(alpha: a);
    final k = dark ? 1.25 : 1.0;
    // Everything is drawn into a layer that fades out at both sides, so
    // the scene dissolves into the page instead of ending in a box.
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());

    // Far ridge (the hills around the city).
    final ridge = Path()..moveTo(0, h * 0.62);
    ridge.cubicTo(w * 0.18, h * 0.30, w * 0.30, h * 0.34, w * 0.42, h * 0.46);
    ridge.cubicTo(w * 0.56, h * 0.60, w * 0.70, h * 0.22, w * 0.86, h * 0.30);
    ridge.cubicTo(w * 0.94, h * 0.34, w, h * 0.42, w, h * 0.46);
    ridge
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(ridge, fill(0.07 * k));

    // City blocks along the horizon.
    final base = h * 0.70;
    final blocks = Path();
    const cols = [
      (0.04, 0.05, 0.20),
      (0.10, 0.04, 0.32),
      (0.15, 0.06, 0.24),
      (0.23, 0.03, 0.40),
      (0.27, 0.05, 0.28),
      (0.52, 0.05, 0.26),
      (0.58, 0.04, 0.36),
      (0.63, 0.06, 0.22),
      (0.76, 0.04, 0.30),
      (0.81, 0.05, 0.20),
      (0.90, 0.04, 0.34),
    ];
    for (final (x, bw, bh) in cols) {
      blocks.addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(w * x, base - h * bh, w * bw, h * bh),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
      );
    }
    // A temple spire (shikhara) with its small flag.
    final sx = w * 0.40, sw = w * 0.07;
    final spire = Path()
      ..moveTo(sx, base)
      ..lineTo(sx, base - h * 0.16)
      ..quadraticBezierTo(
        sx + sw * 0.1,
        base - h * 0.46,
        sx + sw / 2,
        base - h * 0.56,
      )
      ..quadraticBezierTo(
        sx + sw * 0.9,
        base - h * 0.46,
        sx + sw,
        base - h * 0.16,
      )
      ..lineTo(sx + sw, base)
      ..close();
    blocks.addPath(spire, Offset.zero);
    blocks.addRect(Rect.fromLTWH(0, base - 1, w, 2));
    canvas.drawPath(blocks, fill(0.11 * k));
    final flagX = sx + sw / 2;
    canvas.drawLine(
      Offset(flagX, base - h * 0.56),
      Offset(flagX, base - h * 0.68),
      Paint()
        ..color = color.withValues(alpha: 0.14 * k)
        ..strokeWidth = 1.2,
    );
    canvas.drawPath(
      Path()
        ..moveTo(flagX, base - h * 0.68)
        ..lineTo(flagX + w * 0.022, base - h * 0.64)
        ..lineTo(flagX, base - h * 0.60)
        ..close(),
      fill(0.16 * k),
    );

    // The road: a soft band sweeping in from the left.
    final road = Path()
      ..moveTo(0, h)
      ..cubicTo(w * 0.25, h * 0.80, w * 0.55, h * 0.98, w, h * 0.78)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(road, fill(0.12 * k));

    // Dashed centre line following the road's curve.
    final centre = Path()
      ..moveTo(0, h * 1.02)
      ..cubicTo(w * 0.25, h * 0.86, w * 0.55, h * 1.03, w, h * 0.86);
    final dash = Paint()
      ..color = color.withValues(alpha: 0.30 * k)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final m in centre.computeMetrics()) {
      const on = 10.0, off = 10.0;
      for (var d = 0.0; d < m.length; d += on + off) {
        canvas.drawPath(m.extractPath(d, math.min(d + on, m.length)), dash);
      }
    }
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color,
            color,
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.18, 0.82, 1],
        ).createShader(bounds),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandFooterPainter old) =>
      old.color != color || old.dark != dark;
}
