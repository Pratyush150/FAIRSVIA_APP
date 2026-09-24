import 'package:flutter/material.dart';
import '../theme/phosphor_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_elevation.dart';
import '../theme/app_glass.dart';
import 'glass_surface.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';

/// The "◎ Recenter" control that appears over the map when the user has panned
/// away from the vehicle and automatic following is suspended.
///
/// It is deliberately a *labelled* pill rather than another icon button: the
/// icon buttons in the corner are always present and mean "my location", while
/// this one appears only when there is something to go back to, and says so.
/// [visible] animates it in and out with the standard motion tokens instead of
/// popping it into the layout.
class RecenterPill extends StatelessWidget {
  const RecenterPill({
    super.key,
    required this.visible,
    required this.onPressed,
    this.label = 'Recenter',
  });

  final bool visible;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.4),
        // Reduce Motion: no slide, the fade below still shows it arriving.
        duration: AppMotion.of(context, AppMotion.normal),
        curve: AppMotion.emphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.fast,
          child: Semantics(
            button: true,
            label: '$label on the vehicle',
            child: AppGlass.enabled ? _glass(context) : Material(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppSpacing.pill),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  AppHaptics.light();
                  onPressed();
                },
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.pill),
                    boxShadow: AppElevation.float,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm + 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsRegular.gpsFix,
                            size: 20, color: AppColors.accentInk),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          label,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: AppColors.accentText),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Plan F: the same pill in frosted glass (strong fill: it carries text).
  Widget _glass(BuildContext context) => GlassSurface(
        strong: true,
        borderRadius: BorderRadius.circular(AppSpacing.pill),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () {
              AppHaptics.light();
              onPressed();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm + 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsRegular.gpsFix,
                      size: 20, color: AppColors.accentText),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: AppColors.accentText),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
