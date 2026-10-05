import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';

/// A living border for the Home's "Where to?" bar: a brand gradient ring
/// (teal → mint → teal) that rotates slowly and continuously round the
/// child's outline, over a soft teal outer glow. It runs the whole time the
/// Home is visible; Flutter's [TickerMode] pauses it when the route is
/// covered or the app is backgrounded, so it costs nothing off screen.
///
/// Cost: the ring is a foreground [CustomPainter] repainted straight from
/// the animation (no widget rebuilds), and the child sits in its own
/// [RepaintBoundary], so a frame repaints one ring, not the Home.
///
/// Reduce Motion (or [debugDisableLoops], set in tests so `pumpAndSettle`
/// can settle): the same gradient ring and glow, drawn once, not moving.
///
/// The ring follows a rounded rectangle of [borderRadius]; null means a
/// stadium (fully rounded ends, radius = half the height).
class SweepBorder extends StatefulWidget {
  const SweepBorder({
    super.key,
    required this.child,
    this.borderRadius,
    this.width = 2,
    this.lapDuration = defaultLap,
    this.colors,
    this.glow = true,
    this.replayKey,
  });

  final Widget child;
  final BorderRadius? borderRadius;

  /// Stroke width of the ring, drawn just inside the outline so it covers a
  /// border of about the same width.
  final double width;

  /// Time for one full turn of the gradient.
  final Duration lapDuration;

  /// The ring's gradient stops round the loop; defaults to [brandColors].
  final List<Color>? colors;

  /// Whether to draw the soft outer glow under the ring.
  final bool glow;

  /// Kept for callers that restart the effect; the loop restarts from the
  /// top of its turn when it changes.
  final Object? replayKey;

  static const Duration defaultLap = Duration(milliseconds: 5000);

  /// Test hook: when true, looping effects ([SweepBorder] and the poster
  /// shimmer) draw their static frame and schedule no frames, so widget
  /// tests' `pumpAndSettle` settles. Set in `flutter_test_config.dart`.
  static bool debugDisableLoops = false;

  /// Mint highlight used in the brand sweep.
  static const Color mint = Color(0xFF7CF2D2);

  /// Aqua-cyan partner that makes the ring read brighter than a pure teal.
  static const Color cyan = Color(0xFF3DD9F5);

  /// Bright turquoise → cyan → mint → turquoise, closing on itself so the rotation has
  /// no seam. Uses the vivid brand highlight (not the deeper button ink) so
  /// the ring reads bright; one arc dips to the ink so it keeps an edge on
  /// white.
  static List<Color> brandColors(bool dark) => [
    AppColors.highlightFor(dark),
    cyan,
    mint,
    AppColors.highlightFor(dark),
    AppColors.inkFor(dark),
    AppColors.highlightFor(dark),
  ];

  /// The outer glow colour.
  static Color glowColor(bool dark) =>
      AppColors.highlightFor(dark).withValues(alpha: dark ? 0.45 : 0.35);

  @override
  State<SweepBorder> createState() => _SweepBorderState();
}

class _SweepBorderState extends State<SweepBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.lapDuration,
  );
  bool _still = false;

  void _sync() {
    _still = AppMotion.reduced(context) || SweepBorder.debugDisableLoops;
    if (_still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SweepBorder old) {
    super.didUpdateWidget(old);
    _c.duration = widget.lapDuration;
    if (old.replayKey != widget.replayKey && !_still) {
      _c.repeat();
    }
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = widget.borderRadius;
    Widget child = RepaintBoundary(child: widget.child);
    if (widget.glow) {
      final shadow = BoxShadow(
        color: SweepBorder.glowColor(dark),
        blurRadius: 16,
        spreadRadius: 1,
      );
      child = DecoratedBox(
        decoration: r == null
            ? ShapeDecoration(shape: const StadiumBorder(), shadows: [shadow])
            : BoxDecoration(borderRadius: r, boxShadow: [shadow]),
        child: child,
      );
    }
    return CustomPaint(
      foregroundPainter: _SweepPainter(
        progress: _c,
        colors: widget.colors ?? SweepBorder.brandColors(dark),
        width: widget.width,
        radius: r,
      ),
      child: child,
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({
    required this.progress,
    required this.colors,
    required this.width,
    required this.radius,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final List<Color> colors;
  final double width;
  final BorderRadius? radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(width / 2);
    final r = radius ?? BorderRadius.circular(size.height / 2);
    final rrect = r.toRRect(rect);
    final angle = progress.value * 2 * math.pi;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..isAntiAlias = true
      ..shader = SweepGradient(
        colors: colors,
        transform: GradientRotation(angle),
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.progress != progress ||
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
