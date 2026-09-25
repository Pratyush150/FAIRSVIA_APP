import 'package:flutter/widgets.dart';

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
  });

  final Widget child;
  final bool enabled;
  final double scale;

  /// Halo colour while pressed (e.g. [PressScale.brandGlow]); null = none.
  final Color? glow;
  final BorderRadius glowRadius;

  /// The brand halo for tappable cards: the accent, soft in light mode and a
  /// little stronger in dark mode, where a glow has to carry further.
  static Color brandGlow(bool dark) =>
      AppColors.accent.withValues(alpha: dark ? 0.42 : 0.28);

  /// Blur of the halo; small enough to stay inside the 16 dp page gutters.
  static const double glowBlur = 18;

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
    if (glow != null) {
      child = AnimatedContainer(
        duration: AppMotion.normal,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          borderRadius: widget.glowRadius,
          boxShadow: [
            BoxShadow(
              // Same shadow shape either way, so it cross-fades instead of
              // popping in.
              color: _down ? glow : glow.withValues(alpha: 0),
              blurRadius: PressScale.glowBlur,
              spreadRadius: 1,
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
