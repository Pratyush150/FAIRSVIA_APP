import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';

import '../sweep_border.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';

/// Shrinks its child to [scale] while pressed (AppMotion.fast, standard
/// curve) — the tactile press of Home's tiles, cards and banners. Under
/// Reduce Motion it does not scale. Purely visual: it does not handle the
/// tap itself, so wrap it around (or inside) the widget that does.
///
/// With [glow] set, a soft halo in that colour blooms around the child while
/// it is held (shaped by [glowRadius], which should match the card's
/// corners). The halo is a fade, not movement, so it stays on under Reduce
/// Motion — it is the press feedback there. Only this widget rebuilds on a
/// press; the child subtree is reused as is.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.96,
    this.glow,
    this.glowRadius = BorderRadius.zero,
    this.rim = false,
  });

  /// Draws a static brand gradient hairline (teal → mint) round the card
  /// and a soft resting shadow, so the card reads as a lit surface.
  final bool rim;

  final Widget child;
  final bool enabled;
  final double scale;

  /// Halo colour while pressed (e.g. [PressScale.brandGlow]); null = none.
  final Color? glow;
  final BorderRadius glowRadius;

  /// The brand halo for tappable cards: the accent, soft in light mode and a
  /// little stronger in dark mode, where a glow has to carry further.
  static Color brandGlow(bool dark) =>
      AppColors.accent.withValues(alpha: dark ? 0.6 : 0.45);

  /// Blur of the halo; small enough to stay inside the 16 dp page gutters.
  static const double glowBlur = 20;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final scaleOn = widget.enabled && !reduced;
    final glow = widget.enabled ? widget.glow : null;
    Widget child = widget.child;
    if (widget.rim) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      child = CustomPaint(
        foregroundPainter: _RimPainter(widget.glowRadius, dark),
        child: child,
      );
    }
    if (glow != null || widget.rim) {
      child = AnimatedContainer(
        duration: AppMotion.normal,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          borderRadius: widget.glowRadius,
          boxShadow: [
            if (glow != null)
              BoxShadow(
                // Same shadow shape either way, so it cross-fades instead of
                // popping in.
                color: _down ? glow : glow.withValues(alpha: 0),
                blurRadius: PressScale.glowBlur,
                spreadRadius: _down ? 2 : 1,
              ),
            if (widget.rim)
              BoxShadow(
                color: AppColors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: child,
      );
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.enabled && (scaleOn || glow != null)
          ? (_) => _set(true)
          : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: scaleOn && _down ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: child,
      ),
    );
  }
}

/// The static gradient hairline of a [PressScale.rim] card.
class _RimPainter extends CustomPainter {
  _RimPainter(this.radius, this.dark);

  final BorderRadius radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(0.6);
    canvas.drawRRect(
      radius.toRRect(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withValues(alpha: 0.85),
            SweepBorder.mint.withValues(alpha: dark ? 0.6 : 0.75),
            AppColors.accent.withValues(alpha: 0.35),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.dark != dark;
}
