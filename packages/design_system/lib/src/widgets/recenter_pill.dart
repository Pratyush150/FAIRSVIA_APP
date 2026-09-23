import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_elevation.dart';
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
        duration: AppMotion.normal,
        curve: AppMotion.emphasized,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: AppMotion.fast,
          child: Semantics(
            button: true,
            label: '$label on the vehicle',
            child: Material(
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
                        Icon(Icons.gps_fixed_rounded,
                            size: 17, color: AppColors.accentInk),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          label,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: AppColors.accentInk),
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
}
