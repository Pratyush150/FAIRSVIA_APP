import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_elevation.dart';
import '../theme/app_spacing.dart';

/// The floating, rounded bottom panel used across the rider & driver home
/// screens. Rounded top corners, a soft upward shadow, a grab handle, and
/// safe-area-aware padding. Replaces the per-app `_SheetContainer` copies.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.x20,
      AppSpacing.md,
      AppSpacing.x20,
      AppSpacing.x20,
    ),
    this.handle = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool handle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
        boxShadow: AppElevation.lg,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (handle) ...[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.borderDark
                          : AppColors.borderLight,
                      borderRadius: BorderRadius.circular(AppSpacing.pill),
                    ),
                  ),
                ),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}
