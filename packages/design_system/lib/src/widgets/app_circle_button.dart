import 'package:flutter/material.dart';

import '../theme/app_clay3d.dart';
import '../theme/app_elevation.dart';
import '../theme/app_glass.dart';
import 'glass_surface.dart';

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
    if (AppGlass.enabled && background == null) {
      // Plan F: a frosted disc over the map (glass.fill, not the strong
      // fill — it carries a glyph, not text).
      return GlassSurface(
        borderRadius: BorderRadius.circular(size / 2),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: IconButton(
            icon: Icon(icon, size: AppIconSize.mapButton),
            color: foreground ?? scheme.onSurface,
            tooltip: tooltip,
            onPressed: onPressed,
            constraints: BoxConstraints.tightFor(width: size, height: size),
          ),
        ),
      );
    }
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
          icon: Icon(icon, size: AppIconSize.mapButton),
          color: foreground ?? scheme.onSurface,
          tooltip: tooltip,
          onPressed: onPressed,
          constraints: BoxConstraints.tightFor(width: size, height: size),
        ),
      ),
    );
  }
}
