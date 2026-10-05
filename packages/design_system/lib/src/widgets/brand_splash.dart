import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_brand.dart';
import '../theme/app_colors.dart';
import '../theme/app_ink.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'fairsvia_mark.dart';

/// The app's opening sequence: the FAIRSVIA wordmark on the brand canvas,
/// then a short Uber-style launch beat, then a fade into the app.
///
/// Timeline ([AppBrand.splashTotal] = 1.8 s, hard-capped under 2 s):
///  1. 0–450 ms — the lockup (mark + wordmark, Driver pill on the driver app)
///     fades and lifts in.
///  2. 450–1500 ms — a car glides along a road line under the wordmark,
///     drawing the accent-coloured route behind it. It plays **once**; it is
///     not a looping spinner.
///  3. 1500–1800 ms — the whole splash fades out over the (already built) app.
///
/// It hands over on a fixed timer, never on a load event, so it can never
/// delay the app beyond 1.8 s. If start-up work outlives it, the router's
/// first route shows [BrandLaunchHold] — the same final frame with a subtle
/// shimmer running along the road — so the hand-off is seamless.
///
/// Under Reduce Motion it is a static lockup with the road already drawn.
/// All colours come from [AppColors] tokens.
class BrandSplash extends StatefulWidget {
  const BrandSplash({
    super.key,
    required this.onDone,
    this.name = AppBrand.name,
    this.driver = false,
  });

  /// Called once, after the full animation, on the frame the app takes over.
  final VoidCallback onDone;

  /// The wordmark to draw. Defaults to [AppBrand.name].
  final String name;

  /// The driver app's lockup: the driver colourway of the mark and a
  /// "Driver" pill after the wordmark.
  final bool driver;

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _road; // car position / route drawn, 0..1
  late final Animation<double> _out; // the hand-over fade, 1..0
  Timer? _handover;

  @override
  void initState() {
    super.initState();
    final total = AppBrand.splashTotal.inMilliseconds;
    final fadeEnd = AppBrand.splashFadeIn.inMilliseconds / total;
    final roadEnd =
        (AppBrand.splashFadeIn + AppBrand.splashSettle).inMilliseconds / total;
    _c = AnimationController(vsync: this, duration: AppBrand.splashTotal);
    _fade = CurvedAnimation(
      parent: _c,
      curve: Interval(0, fadeEnd, curve: AppMotion.emphasized),
    );
    // The lift runs a little past the fade so the arrival reads as one move.
    _scale = Tween(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: Interval(0, fadeEnd * 1.6, curve: AppMotion.emphasized),
      ),
    );
    // Starts slightly before the wordmark is fully in, so there is no dead
    // beat between the two moves.
    _road = CurvedAnimation(
      parent: _c,
      curve: Interval(fadeEnd * 0.7, roadEnd, curve: Curves.easeInOutCubic),
    );
    _out = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: Interval(roadEnd, 1, curve: Curves.easeOut),
      ),
    );
    // A timer, not an animation-status listener: the handover must happen even
    // if the ticker is muted (the OS backgrounding the app during launch would
    // otherwise strand the user on the splash forever).
    _handover = Timer(AppBrand.splashTotal, () {
      if (mounted) widget.onDone();
    });
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Under Reduce Motion nothing moves; the timer still hands over.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!still) _c.forward();
  }

  @override
  void dispose() {
    _handover?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final driver =
        widget.driver || widget.name.toLowerCase().contains('driver');
    if (AppColors.glass) {
      // FAIRSVIA's own launch motion (see [_FairsviaLaunch]); same timing and
      // hand-over as the classic splash.
      if (still) return _FairsviaLaunch(name: widget.name, driver: driver, t: 1);
      final total = AppBrand.splashTotal.inMilliseconds;
      final playEnd =
          (AppBrand.splashFadeIn + AppBrand.splashSettle).inMilliseconds /
          total;
      return AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Opacity(
          opacity: _out.value,
          child: _FairsviaLaunch(
            name: widget.name,
            driver: driver,
            t: (_c.value / playEnd).clamp(0.0, 1.0),
          ),
        ),
      );
    }
    if (still) {
      // Reduce Motion: the finished frame, no movement; it still hands over
      // on the same timer.
      return _LaunchFrame(name: widget.name, driver: driver, road: 1);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: _out.value,
        child: _LaunchFrame(
          name: widget.name,
          driver: driver,
          lockupOpacity: _fade.value,
          lockupScale: _scale.value,
          road: _road.value,
        ),
      ),
    );
  }
}

/// The splash's final frame, held with a subtle shimmer along the road for as
/// long as start-up work outlives [BrandSplash] (the router's first route).
/// A still frame under Reduce Motion.
class BrandLaunchHold extends StatefulWidget {
  const BrandLaunchHold({super.key, this.name = AppBrand.name, this.driver});

  final String name;

  /// Null reads the Driver lockup from [name].
  final bool? driver;

  @override
  State<BrandLaunchHold> createState() => _BrandLaunchHoldState();
}

class _BrandLaunchHoldState extends State<BrandLaunchHold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.stop();
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
    final driver =
        widget.driver ?? widget.name.toLowerCase().contains('driver');
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (AppColors.glass) {
      if (still) return _FairsviaLaunch(name: widget.name, driver: driver, t: 1);
      return AnimatedBuilder(
        animation: _c,
        builder: (context, _) => _FairsviaLaunch(
          name: widget.name,
          driver: driver,
          t: 1,
          shimmer: _c.value,
        ),
      );
    }
    if (still) {
      return _LaunchFrame(name: widget.name, driver: driver, road: 1);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => _LaunchFrame(
        name: widget.name,
        driver: driver,
        road: 1,
        shimmer: _c.value,
      ),
    );
  }
}

/// One frame of the launch sequence. Shared by [BrandSplash] and
/// [BrandLaunchHold] so the hand-off between them is pixel-identical.
class _LaunchFrame extends StatelessWidget {
  const _LaunchFrame({
    required this.name,
    required this.driver,
    required this.road,
    this.lockupOpacity = 1,
    this.lockupScale = 1,
    this.shimmer,
  });

  final String name;
  final bool driver;
  final double road;
  final double lockupOpacity;
  final double lockupScale;
  final double? shimmer;

  static const double _roadWidth = 176;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final accent = AppColors.highlightFor(dark);
    final track = dark ? AppColors.borderDark : AppColors.borderLight;
    return Scaffold(
      backgroundColor: dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: lockupOpacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: lockupScale,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FairsviaMark(size: 48, driver: driver),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      name,
                      style: InkPaper.on
                          ? InkPaper.serif(44, color: ink)
                          : TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              color: ink,
                            ),
                    ),
                    if (driver) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const FairsviaDriverPill(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // The launch beat: a car drives the route under the wordmark.
            ExcludeSemantics(
              child: SizedBox(
                width: _roadWidth + 24,
                height: 28,
                child: CustomPaint(
                  painter: _RoadPainter(
                    progress: road.clamp(0.0, 1.0),
                    track: track,
                    accent: accent,
                    ink: ink,
                    shimmer: shimmer,
                    // The road itself fades in with the lockup's tail so it
                    // does not pop in ahead of the wordmark.
                    appear: (road * 6).clamp(0.0, 1.0),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoadPainter extends CustomPainter {
  _RoadPainter({
    required this.progress,
    required this.track,
    required this.accent,
    required this.ink,
    required this.appear,
    this.shimmer,
  });

  final double progress;
  final Color track;
  final Color accent;
  final Color ink;
  final double appear;
  final double? shimmer;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 12.0;
    final y = size.height - 6;
    final left = inset;
    final right = size.width - inset;
    final len = right - left;
    final stroke = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    // Road track.
    canvas.drawLine(
      Offset(left, y),
      Offset(right, y),
      stroke..color = track.withValues(alpha: track.a * appear),
    );
    // Route drawn behind the car.
    final x = left + len * progress;
    if (progress > 0) {
      canvas.drawLine(
        Offset(left, y),
        Offset(x, y),
        stroke..color = accent.withValues(alpha: accent.a * appear),
      );
    }
    // The hold state: a soft highlight travelling along the finished route.
    final s = shimmer;
    if (s != null) {
      final cx = left + len * s;
      final glow = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(cx - 28, y - 2, 56, 4));
      canvas.drawLine(
        Offset((cx - 28).clamp(left, right), y),
        Offset((cx + 28).clamp(left, right), y),
        glow,
      );
    }

    // The car: a small side-profile silhouette riding on the line.
    final a = appear;
    final body = Paint()..color = ink.withValues(alpha: ink.a * a);
    const w = 22.0, h = 7.0;
    final bx = x - w / 2;
    final by = y - 4 - h;
    // Cabin.
    final cabin = Path()
      ..moveTo(bx + 5, by + 1)
      ..lineTo(bx + 8, by - 5)
      ..lineTo(bx + 15, by - 5)
      ..lineTo(bx + 19, by + 1)
      ..close();
    canvas.drawPath(cabin, body);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, w, h),
        const Radius.circular(3),
      ),
      body,
    );
    // Window glint in the accent colour ties the car to the route.
    canvas.drawPath(
      Path()
        ..moveTo(bx + 9, by - 3.5)
        ..lineTo(bx + 14.5, by - 3.5)
        ..lineTo(bx + 17, by)
        ..lineTo(bx + 7.5, by)
        ..close(),
      Paint()..color = accent.withValues(alpha: accent.a * a),
    );
    // Wheels, cut out of the road so they read against both themes.
    final wheel = Paint()..color = ink.withValues(alpha: ink.a * a);
    canvas.drawCircle(Offset(bx + 5.5, by + h), 2.6, wheel);
    canvas.drawCircle(Offset(bx + w - 5.5, by + h), 2.6, wheel);
  }

  @override
  bool shouldRepaint(_RoadPainter old) =>
      old.progress != progress ||
      old.shimmer != shimmer ||
      old.appear != appear ||
      old.track != track ||
      old.accent != accent ||
      old.ink != ink;
}

/// FAIRSVIA's launch motion (the shipped glass build), one frame at [t]
/// (0..1 over the play window; 1 is the finished frame):
///  - 0.00–0.35  the Road-F mark pops in (overshoot) while a ripple in the
///    brand blue expands behind it;
///  - 0.20–0.60  the wordmark wipes in left to right;
///  - 0.40–0.85  a curved route draws itself in a blue -> coral gradient;
///  - 0.82–1.00  a coral pin drops onto the end of the route with a bounce.
/// [shimmer] (0..1, looping) runs a soft light along the finished route while
/// start-up work outlives the splash. RideVela's splash (a car on a straight
/// road) stays for every other build.
class _FairsviaLaunch extends StatelessWidget {
  const _FairsviaLaunch({
    required this.name,
    required this.driver,
    required this.t,
    this.shimmer,
  });

  final String name;
  final bool driver;
  final double t;
  final double? shimmer;

  /// The warm second colour of FAIRSVIA's palette (the animations' coral).
  static const Color coral = Color(0xFFFF6B4A);

  static const double _markSize = 52;

  static double _iv(double t, double a, double b, [Curve c = Curves.linear]) =>
      c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final blue = AppColors.highlightFor(dark);
    final mark = _iv(t, 0, 0.35, Curves.easeOutBack);
    final ripple = _iv(t, 0.05, 0.6, Curves.easeOutCubic);
    final word = _iv(t, 0.2, 0.6, Curves.easeOutCubic);
    final route = _iv(t, 0.4, 0.85, Curves.easeInOutCubic);
    final pin = _iv(t, 0.82, 1, Curves.elasticOut);
    final pinIn = _iv(t, 0.82, 0.9);
    return Scaffold(
      backgroundColor:
          dark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _markSize,
                  height: _markSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // The ripple: a ring growing out of the mark and fading.
                      if (ripple > 0 && ripple < 1)
                        IgnorePointer(
                          child: Container(
                            width: _markSize * (1 + 1.4 * ripple),
                            height: _markSize * (1 + 1.4 * ripple),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: blue.withValues(
                                  alpha: 0.45 * (1 - ripple),
                                ),
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      Opacity(
                        opacity: mark.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * mark,
                          child: FairsviaMark(size: _markSize, driver: driver),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // Left-to-right wipe: one Text (stays findable and readable by
                // screen readers), revealed by a moving gradient mask.
                Transform.translate(
                  offset: Offset(-10 * (1 - word), 0),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => LinearGradient(
                      colors: const [Colors.white, Colors.transparent],
                      stops: [word, (word + 0.18).clamp(0.0, 1.0)],
                    ).createShader(r),
                    child: Text(
                      name,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: ink,
                      ),
                    ),
                  ),
                ),
                if (driver) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Opacity(
                    opacity: word,
                    child: const FairsviaDriverPill(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            ExcludeSemantics(
              child: SizedBox(
                width: 220,
                height: 56,
                child: CustomPaint(
                  painter: _RoutePainter(
                    progress: route,
                    pin: pin,
                    pinIn: pinIn,
                    from: blue,
                    to: coral,
                    track: dark ? AppColors.borderDark : AppColors.borderLight,
                    shimmer: shimmer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.progress,
    required this.pin,
    required this.pinIn,
    required this.from,
    required this.to,
    required this.track,
    this.shimmer,
  });

  final double progress;
  final double pin;
  final double pinIn;
  final Color from;
  final Color to;
  final Color track;
  final double? shimmer;

  Path _route(Size s) => Path()
    ..moveTo(10, s.height - 12)
    ..cubicTo(
      s.width * 0.32, s.height - 12,
      s.width * 0.30, 14,
      s.width * 0.55, 18,
    )
    ..cubicTo(
      s.width * 0.78, 22,
      s.width * 0.80, s.height - 14,
      s.width - 18, s.height - 30,
    );

  @override
  void paint(Canvas canvas, Size size) {
    final path = _route(size);
    final metric = path.computeMetrics().first;
    final len = metric.length;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    // Faint full track, so the route has somewhere to go.
    canvas.drawPath(
      path,
      base..color = track.withValues(alpha: track.a * (progress > 0 ? 1 : 0)),
    );
    if (progress > 0) {
      final drawn = metric.extractPath(0, len * progress);
      canvas.drawPath(
        drawn,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4
          ..shader = LinearGradient(colors: [from, to])
              .createShader(Offset.zero & size),
      );
      // The start dot.
      final start = metric.getTangentForOffset(0)!.position;
      canvas.drawCircle(start, 5, Paint()..color = from);
    }
    final s = shimmer;
    if (s != null) {
      final p = metric.getTangentForOffset(len * s)!.position;
      canvas.drawCircle(
        p,
        7,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    if (pinIn > 0) {
      final end = metric.getTangentForOffset(len)!.position;
      // Drops from above and settles (elastic), scaled by [pin].
      final drop = (1 - pinIn) * -18;
      canvas.save();
      canvas.translate(end.dx, end.dy + drop);
      canvas.scale(0.4 + 0.6 * pin.clamp(0.0, 1.2));
      final pinPaint = Paint()..color = to;
      final head = Path()
        ..addOval(Rect.fromCircle(center: const Offset(0, -16), radius: 9))
        ..moveTo(-7, -11)
        ..lineTo(0, 0)
        ..lineTo(7, -11)
        ..close();
      canvas.drawPath(head, pinPaint);
      canvas.drawCircle(const Offset(0, -16), 3.5, Paint()..color = Colors.white);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.progress != progress ||
      old.pin != pin ||
      old.pinIn != pinIn ||
      old.shimmer != shimmer ||
      old.from != from ||
      old.to != to ||
      old.track != track;
}

/// Shows [BrandSplash] over [child] for one launch, then cross-fades the app
/// in. Drop it in `MaterialApp.builder` so the splash covers whatever the
/// router puts up first (auth gate, home, a restored ride) without any screen
/// needing to know about it.
///
/// It is a one-shot per widget lifetime: rebuilds of [child] underneath (the
/// router settling, a bloc emitting) do not restart the animation.
class BrandSplashGate extends StatefulWidget {
  const BrandSplashGate({
    super.key,
    required this.child,
    this.enabled = true,
    this.driver = false,
  });

  final Widget child;

  /// The driver app's lockup (see [BrandSplash.driver]).
  final bool driver;

  /// False skips the splash entirely — used by widget tests, which should not
  /// have to pump 1.4 s of brand animation before they can find anything.
  final bool enabled;

  @override
  State<BrandSplashGate> createState() => _BrandSplashGateState();
}

class _BrandSplashGateState extends State<BrandSplashGate> {
  late bool _showing = widget.enabled;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showing)
          Positioned.fill(
            child: TickerMode(
              enabled: true,
              child: BrandSplash(
                driver: widget.driver,
                onDone: () => setState(() => _showing = false),
              ),
            ),
          ),
      ],
    );
  }
}
