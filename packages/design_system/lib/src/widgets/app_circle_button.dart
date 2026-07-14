import 'package:flutter/material.dart';

import '../theme/app_elevation.dart';

/// A circular icon button that floats over the map (menu, recenter, back).
/// Replaces the `_CircleButton` copies in the rider & driver apps.
class AppCircleButton extends StatelessWidget {
  const AppCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 48,
    this.foreground,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: background ?? scheme.surface,
        shape: BoxShape.circle,
        boxShadow: AppElevation.float,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          icon: Icon(icon, size: 22),
          color: foreground ?? scheme.onSurface,
          tooltip: tooltip,
          onPressed: onPressed,
          constraints: BoxConstraints.tightFor(width: size, height: size),
        ),
      ),
    );
  }
}
