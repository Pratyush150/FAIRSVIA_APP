import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_elevation.dart';
import '../theme/app_glass.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'glass_surface.dart';

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
    this.onHandleTap,
    this.handleLabel,
    this.onHandleDrag,
    this.chromeless = false,
  });

  /// Plan F (`THEME=glass`) only — ignored by every other build.
  ///
  /// Makes the grab handle a control: tapping it (and a vertical fling on it,
  /// reported to [onHandleDrag] as the fling velocity, negative = up) toggles
  /// a compact/expanded sheet. [handleLabel] is what a screen reader says.
  final VoidCallback? onHandleTap;
  final String? handleLabel;
  final ValueChanged<double>? onHandleDrag;

  /// Plan F only: draw no panel at all — the content (e.g. the floating
  /// "Where to?" pill) floats over the map by itself. Animates: the glass
  /// dissolves into the map and condenses back around the next phase.
  final bool chromeless;

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
    if (AppGlass.enabled) return _glass(context, media);
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

extension on AppSheet {
  /// Plan F: a floating glass card, inset [AppGlass.sheetInset] from the
  /// screen edges with [AppGlass.sheetRadius] corners, the map visible all
  /// round it. Margins, padding and the glass itself animate between phases
  /// (the "morph"); under Reduce Motion they snap.
  Widget _glass(BuildContext context, MediaQueryData media) {
    // Large text: the floating inset and the side padding shrink so rows
    // keep the width they need (at 2x text, 12 px margins overflowed the
    // ride-option rows on a 360-wide phone). Accessibility beats the float.
    final roomy = media.textScaler.scale(10) <= 13;
    final inset = roomy ? AppGlass.sheetInset : 6.0;
    // Content sits a little closer to the glass edge than on the solid
    // sheet (16, not 20), which gives back most of the width the float
    // takes, so headlines wrap and truncate as they do on the solid sheet.
    final maxSide = roomy ? 16.0 : 12.0;
    final side = EdgeInsets.fromLTRB(
      padding.left > maxSide ? maxSide : padding.left,
      padding.top,
      padding.right > maxSide ? maxSide : padding.right,
      padding.bottom,
    );
    final bottomGap =
        media.padding.bottom > inset ? media.padding.bottom : inset;
    final margin = EdgeInsets.fromLTRB(inset, 0, inset, bottomGap);
    // Same caps as the solid sheet, on the whole sheet (card + bottom gap).
    var maxHeight = media.size.height - media.padding.top - AppSpacing.md;
    final fraction = maxHeightFraction;
    if (fraction != null) {
      final capped = media.size.height * fraction;
      if (capped < maxHeight) maxHeight = capped;
    }
    final duration = AppMotion.of(context, AppMotion.slow);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight > 0 ? maxHeight : 0),
      child: Padding(
        padding: margin,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: chromeless ? 0 : 1),
          duration: duration,
          curve: AppMotion.standard,
          builder: (context, presence, content) => GlassSurface(
            strong: true,
            presence: presence,
            child: content!,
          ),
          child: AnimatedPadding(
            duration: duration,
            curve: AppMotion.standard,
            padding: chromeless
                ? EdgeInsets.zero
                : EdgeInsets.fromLTRB(
                    side.left,
                    handle ? 0 : side.top,
                    side.right,
                    side.bottom,
                  ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (handle && !chromeless) _GlassHandle(sheet: this),
                Flexible(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    removeBottom: true,
                    child: _FadeWhenMore(child: child),
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
      ),
    );
  }
}

/// Glass sheets: the scrolling content fades out over its last few pixels
/// while there is more below — the Apple Maps cue that the card scrolls —
/// and is drawn plainly (no mask layer) when everything fits.
class _FadeWhenMore extends StatefulWidget {
  const _FadeWhenMore({required this.child});

  final Widget child;

  @override
  State<_FadeWhenMore> createState() => _FadeWhenMoreState();
}

class _FadeWhenMoreState extends State<_FadeWhenMore> {
  bool _more = false;
  // Keeps the scroll view (and its offset) when the mask comes and goes.
  final GlobalKey _scrollKey = GlobalKey();

  bool _onMetrics(ScrollMetricsNotification n) {
    _update(n.metrics);
    return false;
  }

  bool _onScroll(ScrollUpdateNotification n) {
    _update(n.metrics);
    return false;
  }

  void _update(ScrollMetrics m) {
    final more = m.extentAfter > 1;
    if (more != _more) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    Widget scroll =
        SingleChildScrollView(key: _scrollKey, child: widget.child);
    if (_more) {
      scroll = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          stops: [r.height <= 32 ? 0 : (r.height - 32) / r.height, 1],
        ).createShader(r),
        child: scroll,
      );
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onMetrics,
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: _onScroll,
        child: scroll,
      ),
    );
  }
}

/// The glass sheet's grab handle. Plain decoration unless the sheet gave it
/// a job ([AppSheet.onHandleTap]); then it is a 48-tall button (the touch
/// floor) that also takes a vertical fling.
class _GlassHandle extends StatelessWidget {
  const _GlassHandle({required this.sheet});

  final AppSheet sheet;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bar = Center(
      child: Container(
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: isDark ? const Color(0x59FFFFFF) : const Color(0x400F1417),
          borderRadius: BorderRadius.circular(AppSpacing.pill),
        ),
      ),
    );
    final tap = sheet.onHandleTap;
    if (tap == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 14),
        child: bar,
      );
    }
    return Semantics(
      button: true,
      label: sheet.handleLabel,
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: tap,
        onVerticalDragEnd: sheet.onHandleDrag == null
            ? null
            : (d) => sheet.onHandleDrag!(d.primaryVelocity ?? 0),
        // 48 tall: Android's touch floor (iOS asks 44).
        child: SizedBox(height: 48, child: bar),
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
  }
}
