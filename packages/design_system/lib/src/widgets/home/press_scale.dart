import 'package:flutter/widgets.dart';

import '../../theme/app_motion.dart';

/// Shrinks its child to [scale] while pressed (AppMotion.fast, standard
/// curve) — the tactile press of Home's tiles, cards and banners. Under
/// Reduce Motion it does not scale. Purely visual: it does not handle the
/// tap itself, so wrap it around (or inside) the widget that does.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = 0.96,
  });

  final Widget child;
  final bool enabled;
  final double scale;

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
    final on = widget.enabled && !AppMotion.reduced(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: on ? (_) => _set(true) : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: on && _down ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        child: widget.child,
      ),
    );
  }
}
