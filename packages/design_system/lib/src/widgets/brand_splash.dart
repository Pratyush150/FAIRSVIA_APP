import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_brand.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'ridevela_mark.dart';

/// The app's opening frame: the wordmark on the brand canvas, nothing else.
///
/// This is a **brand signature, not a loading screen** — there is deliberately
/// no spinner. It runs for a fixed [AppBrand.splashTotal] and then calls
/// [onDone]; whatever the app is doing in the background (dependency wiring,
/// token restore) keeps doing it underneath. If that work outlives the splash
/// the app's own router shows its own progress, which is where a spinner
/// belongs.
///
/// Timing follows the brand spec: fade in, settle, hand over.
class BrandSplash extends StatefulWidget {
  const BrandSplash({
    super.key,
    required this.onDone,
    this.name = AppBrand.name,
  });

  /// Called once, after the full animation, on the frame the app takes over.
  final VoidCallback onDone;

  /// The wordmark to draw. Defaults to [AppBrand.name].
  final String name;

  @override
  State<BrandSplash> createState() => _BrandSplashState();
}

class _BrandSplashState extends State<BrandSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<double> _rule; // the underline sweeping out
  Timer? _handover;

  @override
  void initState() {
    super.initState();
    final total = AppBrand.splashTotal.inMilliseconds;
    final fadeEnd = AppBrand.splashFadeIn.inMilliseconds / total;
    final settleEnd =
        (AppBrand.splashFadeIn + AppBrand.splashSettle).inMilliseconds / total;
    _c = AnimationController(vsync: this, duration: AppBrand.splashTotal);
    // 0 → fadeEnd: the wordmark arrives.
    _fade = CurvedAnimation(
      parent: _c,
      curve: Interval(0, fadeEnd, curve: AppMotion.emphasized),
    );
    // Runs past the fade into the settle window so the lift keeps going for a
    // beat after the text is fully opaque — that overlap is what makes it read
    // as a signature rather than two separate animations.
    _scale = Tween(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: Interval(0, settleEnd, curve: AppMotion.emphasized),
      ),
    );
    _rule = CurvedAnimation(
      parent: _c,
      curve: Interval(fadeEnd, settleEnd, curve: AppMotion.emphasized),
    );
    _c.forward();
    // A timer, not an animation-status listener: the handover must happen even
    // if the ticker is muted (the OS backgrounding the app during launch would
    // otherwise strand the user on the splash forever).
    _handover = Timer(AppBrand.splashTotal, () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _handover?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    return Scaffold(
      backgroundColor: dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The lockup: mark + wordmark, the same on every screen.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RideVelaMark(
                      size: 48,
                      driver: widget.name.toLowerCase().contains('driver'),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      widget.name,
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        color: ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                // A short brand rule that draws itself out under the lockup,
                // doubling as the loading indicator.
                AnimatedBuilder(
                  animation: _rule,
                  builder: (_, _) => Container(
                    width: 56 * _rule.value,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.highlightFor(dark),
                      borderRadius: BorderRadius.circular(AppSpacing.pill),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [BrandSplash] over [child] for one launch, then cross-fades the app
/// in. Drop it in `MaterialApp.builder` so the splash covers whatever the
/// router puts up first (auth gate, home, a restored ride) without any screen
/// needing to know about it.
///
/// It is a one-shot per widget lifetime: rebuilds of [child] underneath (the
/// router settling, a bloc emitting) do not restart the animation.
class BrandSplashGate extends StatefulWidget {
  const BrandSplashGate({super.key, required this.child, this.enabled = true});

  final Widget child;

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
                onDone: () => setState(() => _showing = false),
              ),
            ),
          ),
      ],
    );
  }
}
