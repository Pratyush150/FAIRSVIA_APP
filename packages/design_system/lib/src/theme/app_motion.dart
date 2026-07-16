import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Motion design tokens. Centralising durations + curves keeps animation across
/// all three apps feeling like one system: short, eased, and never bouncy on
/// functional UI (the Uber/Airbnb house style — motion that clarifies, not
/// decorates).
abstract final class AppMotion {
  // Durations.
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);

  /// Entrance reveal for content appearing on screen.
  static const Duration reveal = Duration(milliseconds: 460);

  /// Per-item delay when staggering a list/section into view.
  static const Duration stagger = Duration(milliseconds: 55);

  // Curves.
  static const Curve standard = Curves.easeOutCubic; // general transitions
  static const Curve emphasized = Curves.easeOutQuart; // entrances
  static const Curve exit = Curves.easeInCubic; // things leaving
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
/// entrance with one call instead of hand-rolled controllers.
extension AppReveal on Widget {
  /// Gentle fade + rise — the default way a block of content appears.
  Widget reveal({Duration? delay}) => animate(delay: delay)
      .fadeIn(duration: AppMotion.reveal, curve: AppMotion.emphasized)
      .moveY(
        begin: 14,
        end: 0,
        duration: AppMotion.reveal,
        curve: AppMotion.emphasized,
      );

  /// Reveal item at [index] in a list, each one slightly after the last.
  Widget revealStaggered(int index, {Duration? base}) =>
      reveal(delay: (base ?? Duration.zero) + AppMotion.stagger * index);

  /// Soft scale + fade for elements that pop into place (medallions, badges).
  Widget popIn({Duration? delay}) => animate(delay: delay)
      .fadeIn(duration: AppMotion.normal, curve: AppMotion.standard)
      .scaleXY(
        begin: 0.85,
        end: 1,
        duration: AppMotion.normal,
        curve: AppMotion.emphasized,
      );
}
