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
    // Never let the sheet grow under the status bar / Dynamic Island: cap its
    // height at the screen minus the top safe-area inset (plus a small margin)
    // so tall content (ride options with surge/error lines, completed-trip
    // sheet with tip picker) scrolls inside the sheet instead of pushing the
    // header off the top of the screen. Seen on iPhone 17 (iOS 26.5).
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height - media.padding.top - AppSpacing.md;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight > 0 ? maxHeight : 0),
      child: _SheetBody(
        isDark: isDark,
        padding: padding,
        handle: handle,
        child: child,
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.isDark,
    required this.padding,
    required this.handle,
    required this.child,
  });

  final bool isDark;
  final EdgeInsets padding;
  final bool handle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
              // Scroll the content when it can't fit the available height —
              // notably when the soft keyboard opens over a field in the sheet
              // (promo code, custom tip). Flexible + shrink-wrapping scroll view
              // keeps the sheet compact when content fits, and scrolls (instead
              // of overflowing) when it doesn't.
              Flexible(child: SingleChildScrollView(child: child)),
            ],
          ),
        ),
      ),
    );
  }
}
