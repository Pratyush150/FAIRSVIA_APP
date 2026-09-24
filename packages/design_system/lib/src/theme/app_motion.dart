import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Motion design tokens. Centralising durations + curves keeps animation across
/// all three apps feeling like one system: short, eased, and never bouncy on
/// functional UI (the Uber/Airbnb house style — motion that clarifies, not
/// decorates).
///
/// The scale is the audit's (4.1): **100 / 200 / 350 / 500 ms**, with the
/// Material 3 emphasized curves for things entering and leaving. Widgets use
/// these names, never a literal `Duration(milliseconds: …)`, for UI motion.
///
/// Reduce Motion (audit 4.2): check [reduced] (Android "Remove animations",
/// iOS Reduce Motion) and swap movement for a cross-fade — or use the
/// [AppReveal] helpers and [MotionAware], which do it for you.
abstract final class AppMotion {
  // Durations — the whole scale is these four steps.

  /// 100 ms — micro feedback: a press, a toggle, a chip's fill, a tick.
  static const Duration fast = Duration(milliseconds: 100);

  /// 200 ms — small swaps: a selection, a text change, a banner sliding in.
  static const Duration normal = Duration(milliseconds: 200);

  /// 350 ms — larger moves: a sheet changing phase, a card popping in.
  static const Duration slow = Duration(milliseconds: 350);

  /// 500 ms — the longest step: a block of content revealing on a new screen,
  /// the brand's opening beats.
  static const Duration slower = Duration(milliseconds: 500);

  /// Entrance reveal for content appearing on screen (= [slower]).
  static const Duration reveal = slower;

  /// Per-item delay when staggering a list/section into view.
  static const Duration stagger = Duration(milliseconds: 50);

  // Curves.

  /// General transitions between two resting states.
  static const Curve standard = Curves.easeOutCubic;

  /// ease.enter — M3 emphasized decelerate: things arriving on screen.
  static const Curve enter = Easing.emphasizedDecelerate;

  /// ease.exit — M3 emphasized accelerate: things leaving the screen.
  static const Curve exit = Easing.emphasizedAccelerate;

  /// The entrance curve under its older name; same as [enter].
  static const Curve emphasized = enter;

  /// True when the OS asks for less motion: Android's "Remove animations",
  /// iOS Reduce Motion (Flutter surfaces both as
  /// [MediaQueryData.disableAnimations]). Movement, scaling and looping
  /// effects should stop; a plain cross-fade is fine.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or [Duration.zero] under Reduce Motion — for implicit animations
  /// that only move or resize (AnimatedSize, AnimatedAlign, scroll-into-view).
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// Semantic haptics wrapper. Call sites read intent (`AppHaptics.selection()`),
/// not the raw platform API, so feedback is consistent and tunable in one place.
/// No-ops silently on platforms without a haptics engine.
abstract final class AppHaptics {
  /// A light tick for discrete selection changes (tier, chip, toggle).
  static void selection() => HapticFeedback.selectionClick();

  /// A soft tap for primary button presses.
  static void light() => HapticFeedback.lightImpact();

  /// A firmer bump for committing an action (confirm ride, accept offer).
  static void medium() => HapticFeedback.mediumImpact();

  /// Success confirmation (trip complete, OTP verified).
  static void success() => HapticFeedback.mediumImpact();

  /// A strong hit for an interrupting/urgent event (incoming offer).
  static void heavy() => HapticFeedback.heavyImpact();
}

/// Reveal helpers built on flutter_animate, so screens get a consistent, tasteful
/// entrance with one call instead of hand-rolled controllers. All of them honour
/// Reduce Motion: movement and scaling drop out, leaving a short fade.
extension AppReveal on Widget {
  /// Gentle fade + rise — the default way a block of content appears.
  Widget reveal({Duration? delay}) => motion(
        (w) => w
            .animate(delay: delay)
            .fadeIn(duration: AppMotion.reveal, curve: AppMotion.enter)
            .moveY(
              begin: 14,
              end: 0,
              duration: AppMotion.reveal,
              curve: AppMotion.enter,
            ),
      );

  /// Reveal item at [index] in a list, each one slightly after the last.
  Widget revealStaggered(int index, {Duration? base}) =>
      reveal(delay: (base ?? Duration.zero) + AppMotion.stagger * index);

  /// Soft scale + fade for elements that pop into place (medallions, badges).
  Widget popIn({Duration? delay}) => motion(
        (w) => w
            .animate(delay: delay)
            .fadeIn(duration: AppMotion.normal, curve: AppMotion.standard)
            .scaleXY(
              begin: 0.85,
              end: 1,
              duration: AppMotion.slow,
              curve: AppMotion.enter,
            ),
      );

  /// Runs [animated] (typically a flutter_animate chain on this widget)
  /// normally; under Reduce Motion shows this widget with a plain
  /// [AppMotion.fast] fade instead — or with no effect at all when
  /// [fadeWhenReduced] is false (a decorative pop that carries no meaning).
  Widget motion(
    Widget Function(Widget child) animated, {
    bool fadeWhenReduced = true,
  }) =>
      MotionAware(
        animated: animated,
        fadeWhenReduced: fadeWhenReduced,
        child: this,
      );
}

/// Chooses between a widget's full entrance effect and its Reduce Motion
/// stand-in at build time, from [AppMotion.reduced]. See [AppReveal.motion].
class MotionAware extends StatelessWidget {
  const MotionAware({
    super.key,
    required this.animated,
    required this.child,
    this.fadeWhenReduced = true,
  });

  final Widget Function(Widget child) animated;
  final Widget child;
  final bool fadeWhenReduced;

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.reduced(context)) return animated(child);
    return fadeWhenReduced
        ? child.animate().fadeIn(duration: AppMotion.fast)
        : child;
  }
}
