import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_ink.dart';

/// An animated "searching" radar — concentric rings that expand and fade out,
/// with a soft rotating sweep and a steady centre dot. Replaces a bland spinner
/// on the rider's "finding your driver" state with something that reads as the
/// system actively looking around the map.
class PulseRadar extends StatefulWidget {
  const PulseRadar({
    super.key,
    this.size = 104,
    this.color,
    this.child,
  });

  final double size;
  final Color? color;

  /// Optional glyph shown at the centre (e.g. a car icon).
  final Widget? child;

  @override
  State<PulseRadar> createState() => _PulseRadarState();
}

class _PulseRadarState extends State<PulseRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

  // Reduce Motion / Remove animations: the rings hold still (audit 4.2).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c
        ..stop()
        ..value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Depend on the theme: the ink colours below must follow a light/dark
    // switch made while the app is open.
    Theme.of(context);
    // THEME=ink: teal, the colour kept for the one live thing on screen.
    final color = widget.color ??
        (InkPaper.on ? AppColors.highlight : AppColors.accent);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => CustomPaint(
          painter: _RadarPainter(progress: _c.value, color: color),
          child: child,
        ),
        child: widget.child == null
            ? null
            : Center(child: widget.child),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.color});

  final double progress; // 0..1, looping
  final Color color;

  static const int _rings = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;

    // Plan E (THEME=ink): three thin teal circles, no fill, no sweep.
    if (InkPaper.on) {
      for (var i = 0; i < _rings; i++) {
        final t = (progress + i / _rings) % 1.0;
        canvas.drawCircle(
          center,
          maxR * (0.25 + 0.75 * t),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 1 - t * 0.85),
        );
      }
      return;
    }

    // Expanding, fading concentric rings, phase-staggered so one is always
    // near the centre as the outer one dissolves.
    for (var i = 0; i < _rings; i++) {
      final t = (progress + i / _rings) % 1.0;
      final r = maxR * t;
      final opacity = (1.0 - t) * 0.55;
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: opacity);
      canvas.drawCircle(center, r, ring);

      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: opacity * 0.12);
      canvas.drawCircle(center, r, fill);
    }

    // Rotating sweep wedge.
    final sweepAngle = progress * 2 * math.pi;
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle,
        endAngle: sweepAngle + math.pi / 2,
        colors: [color.withValues(alpha: 0.0), color.withValues(alpha: 0.22)],
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR, sweep);

    // Steady centre dot.
    canvas.drawCircle(
      center,
      5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}
