import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// A light that travels around its child's outline: a short gradient "comet"
/// (brand accent into highlight) drawn on top of the child's own border.
/// Made for the Home's "Where to?" bar — it runs a few laps when the bar
/// first shows (and again on [replayKey] change), then fades out, leaving the
/// bar's own border. It never loops forever: the Home is on screen for a long
/// time and a constant chase would be noise (and battery).
///
/// Cost: the light is a foreground [CustomPainter] repainted straight from
/// the animation (no widget rebuilds), inside its own [RepaintBoundary], so a
/// lap repaints one ring, not the Home. Reduce Motion: nothing is drawn.
///
/// The ring follows a rounded rectangle of [borderRadius]; null means a
/// stadium (fully rounded ends, radius = half the height).
class SweepBorder extends StatefulWidget {
  const SweepBorder({
    super.key,
    required this.child,
    this.borderRadius,
    this.width = 2,
    this.laps = 2,
    this.lapDuration = defaultLap,
    this.colors,
    this.replayKey,
  });

  final Widget child;
  final BorderRadius? borderRadius;

  /// Stroke width of the light, centred on the outline's inset edge so it
  /// covers a border of about the same width.
  final double width;

  /// How many times the light goes round before it fades.
  final int laps;
  final Duration lapDuration;

  /// The comet's colours from tail to head; defaults to [brandColors].
  final List<Color>? colors;

  /// Change it to run the laps again (e.g. when the Home returns).
  final Object? replayKey;

  static const Duration defaultLap = Duration(milliseconds: 2400);

  /// Tail → head: transparent accent, accent, the highlight at the head.
  static List<Color> brandColors(bool dark) => [
    AppColors.accent.withValues(alpha: 0),
    AppColors.accent,
    AppColors.highlightFor(dark),
  ];

  @override
  State<SweepBorder> createState() => _SweepBorderState();
}

class _SweepBorderState extends State<SweepBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.lapDuration * widget.laps,
  );
  bool _reduced = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AppMotion.reduced(context);
    if (_reduced) {
      _c.stop();
    } else if (!_started) {
      _started = true;
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(SweepBorder old) {
    super.didUpdateWidget(old);
    _c.duration = widget.lapDuration * widget.laps;
    if (old.replayKey != widget.replayKey && !_reduced) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduced) return widget.child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      foregroundPainter: _SweepPainter(
        progress: _c,
        laps: widget.laps,
        colors: widget.colors ?? SweepBorder.brandColors(dark),
        width: widget.width,
        radius: widget.borderRadius,
      ),
      child: RepaintBoundary(child: widget.child),
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.progress,
    required this.laps,
    required this.colors,
    required this.width,
    required this.radius,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final int laps;
  final List<Color> colors;
  final double width;
  final BorderRadius? radius;

  /// Share of the run over which the light fades in, and out at the end.
  static const double _fade = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1 || size.isEmpty) return;
    final alpha = (math.min(t, 1 - t) / _fade).clamp(0.0, 1.0);
    final rect = (Offset.zero & size).deflate(width / 2);
    final r = radius ?? BorderRadius.circular(size.height / 2);
    final rrect = r.toRRect(rect);
    // The comet covers a quarter turn, its head at the rotation angle.
    final angle = t * laps * 2 * math.pi;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = SweepGradient(
        colors: [
          for (final c in colors) c.withValues(alpha: c.a * alpha),
          colors.first.withValues(alpha: 0),
        ],
        stops: [
          for (var i = 0; i < colors.length; i++)
            0.75 + 0.25 * i / (colors.length - 1) - (i == colors.length - 1 ? 0.001 : 0),
          1.0,
        ],
        transform: GradientRotation(angle),
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.progress != progress ||
      old.laps != laps ||
      old.width != width ||
      old.radius != radius ||
      !_sameColors(old.colors, colors);

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
