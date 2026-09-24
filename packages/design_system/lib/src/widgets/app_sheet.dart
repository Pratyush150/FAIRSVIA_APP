import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_elevation.dart';
import '../theme/app_spacing.dart';
import '../theme/app_variant.dart';

/// The floating, rounded bottom panel used across the rider & driver home
/// screens. Rounded top corners, a soft upward shadow, a grab handle, and
/// safe-area-aware padding. Replaces the per-app `_SheetContainer` copies.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.child,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.x20,
      AppSpacing.md,
      AppSpacing.x20,
      AppSpacing.x20,
    ),
    this.handle = true,
    this.maxHeightFraction,
  });

  final Widget child;

  /// Optional cap on the sheet height as a fraction of the screen height
  /// (e.g. 0.6). Use it for phases where the map behind the sheet matters —
  /// the ride-options sheet otherwise grows to ~95% of the screen and hides
  /// the routed polyline and markers. Content scrolls inside the sheet.
  final double? maxHeightFraction;

  /// Optional pinned footer (e.g. the primary call-to-action). Rendered below
  /// the scrollable [child] and never scrolled out of view, so a tall sheet
  /// still shows its main action without the user having to scroll for it.
  final Widget? footer;
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
    var maxHeight = media.size.height - media.padding.top - AppSpacing.md;
    final fraction = maxHeightFraction;
    if (fraction != null) {
      final capped = media.size.height * fraction;
      if (capped < maxHeight) maxHeight = capped;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight > 0 ? maxHeight : 0),
      child: _SheetBody(
        isDark: isDark,
        padding: padding,
        handle: handle,
        footer: footer,
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
    required this.footer,
    required this.child,
  });

  final bool isDark;
  final EdgeInsets padding;
  final bool handle;
  final Widget? footer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sheet = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // Plan D: warm paper, so the white cards on it read as cards.
        color: AppVariant.local
            ? LocalColour.paperFor(isDark)
            : Theme.of(context).colorScheme.surface,
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
              Flexible(
                // The sheet is already laid out below the top inset (see
                // AppSheet.build), so inner scrollables must not re-apply
                // MediaQuery.padding.top as leading padding — without this a
                // ListView inside the sheet showed a phantom status-bar-sized
                // gap above its first row.
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: SingleChildScrollView(child: child),
                ),
              ),
              if (footer != null) ...[
                const SizedBox(height: AppSpacing.md),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
    if (!AppVariant.local) return sheet;
    // Plan D's signature edge: a thin marigold rule along the rounded top.
    return CustomPaint(
      foregroundPainter: const MarigoldRulePainter(),
      child: sheet,
    );
  }
}

/// Plan D: a thin marigold rule traced along a sheet's rounded top edge,
/// fading out into the corners like a strung garland. Decorative only (the
/// accent never carries meaning).
class MarigoldRulePainter extends CustomPainter {
  const MarigoldRulePainter({
    this.radius = AppSpacing.radiusXl,
    this.width = 2.5,
  });

  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final r = radius;
    final inset = width / 2;
    final path = Path()
      ..moveTo(inset, r)
      ..arcToPoint(Offset(r, inset), radius: Radius.circular(r - inset))
      ..lineTo(size.width - r, inset)
      ..arcToPoint(Offset(size.width - inset, r),
          radius: Radius.circular(r - inset));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(colors: [
        LocalColour.marigold.withValues(alpha: 0),
        LocalColour.marigold,
        LocalColour.marigold,
        LocalColour.marigold.withValues(alpha: 0),
      ], stops: const [0, 0.14, 0.86, 1])
          .createShader(Offset.zero & Size(size.width, r));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MarigoldRulePainter old) =>
      old.radius != radius || old.width != width;
}
