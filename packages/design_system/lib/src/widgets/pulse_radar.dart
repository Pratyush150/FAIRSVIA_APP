import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_variant.dart';
import 'kolam.dart';
import '../theme/app_ink.dart';

/// The one timing rule for every "finding your driver" ring — the sheet's
/// [PulseRadar] and the map's pickup radar (`AppMap.pulseAt`) — so the two
/// breathe together, slowly, instead of strobing.
///
/// Three rings, staggered by a third of [period]. Each one grows on an
/// ease-out (fast off the pin, settling as it spreads) and fades in over its
/// first few percent, then out, so a ring is invisible at both ends of its
/// life: the loop never "pops" when a ring wraps back to the centre.
abstract final class CalmPulse {
  /// 3.4 s (was 2.4 s): the owner found the faster loop busy (2026-09-25).
  static const Duration period = Duration(milliseconds: 3400);
  static const int rings = 3;

  /// Peak opacity a ring reaches.
  static const double peak = 0.38;

  /// Ring [i] at loop time [t] (0..1): (spread 0..1, opacity 0..[peak]).
  /// Pure, for tests.
  static (double, double) ring(double t, int i) {
    final p = ((t + i / rings) % 1.0 + 1.0) % 1.0;
    final spread = Curves.easeOutCubic.transform(p);
    // Fade in over the first 12%, then out on an ease-in so the tail lingers.
    final fadeIn = (p / 0.12).clamp(0.0, 1.0);
    final fadeOut = math.pow(1.0 - p, 1.6).toDouble();
    return (spread, peak * fadeIn * fadeOut);
  }

  /// All [rings] at loop time [t].
  static List<(double, double)> all(double t) =>
      [for (var i = 0; i < rings; i++) ring(t, i)];

  /// Where in the loop the wall clock is. Starting an animation here rather
  /// than at 0 means a widget that is rebuilt or remounted (a sheet swap, a
  /// status-text change) picks the rings up where they were, with no restart.
  static double phaseNow([Duration p = period]) =>
      (DateTime.now().millisecondsSinceEpoch % p.inMilliseconds) /
      p.inMilliseconds;

  /// Still frame for Reduce Motion: rings spread evenly, fully drawn.
  static const double stillPhase = 0.2;
}

/// An animated "searching" radar — concentric rings that expand and fade out,
/// round a steady centre dot, on the calm [CalmPulse] timing. Replaces a spinner
/// on the rider's "finding your driver" state with something that reads as the
/// system actively looking around the map.
///
/// Plan D (`THEME=local`) draws the kolam-dot loader instead ([Kolam]): dots
/// that build into a kolam at the centre, wrapped by a marigold line. Under
/// Reduce Motion it shows the finished kolam, still.
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
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: AppVariant.local ? Kolam.period : CalmPulse.period);
  bool _still = false;

  // Reduce Motion / Remove animations: the rings hold still (audit 4.2).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      _c
        ..stop()
        ..value = AppVariant.local ? 0 : CalmPulse.stillPhase;
    } else if (!_c.isAnimating) {
      // Resume from the wall-clock phase, not 0: one controller for the
      // widget's life, and even a remount does not visibly restart the rings.
      _c
        ..value = CalmPulse.phaseNow(_c.duration!)
        ..repeat();
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
          painter: AppVariant.local
              ? KolamRadarPainter(
                  progress: _c.value,
                  color: color,
                  still: _still,
                  hollowCentre: widget.child != null,
                )
              : _RadarPainter(progress: _c.value, color: color),
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

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide / 2;

    // Plan E (THEME=ink): three thin teal circles, no fill, no sweep.
    if (InkPaper.on) {
      for (final (spread, opacity) in CalmPulse.all(progress)) {
        canvas.drawCircle(
          center,
          maxR * (0.25 + 0.75 * spread),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: opacity * 1.6),
        );
      }
      return;
    }

    // Expanding, fading concentric rings on the shared calm timing: soft
    // filled discs with a feathered rim, no hard stroke edge.
    for (final (spread, opacity) in CalmPulse.all(progress)) {
      if (opacity <= 0.002) continue;
      final r = maxR * (0.18 + 0.82 * spread);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: opacity * 0.10),
              color.withValues(alpha: opacity * 0.22),
              color.withValues(alpha: opacity * 0.55),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.7, 0.93, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    // (No rotating sweep: a wedge spinning every loop read as busy, not calm.)

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
