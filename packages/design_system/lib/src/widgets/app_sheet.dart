import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_elevation.dart';
import '../theme/app_glass.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_variant.dart';
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
    this.height,
    this.chromeless = false,
    this.minHeightFraction,
    this.fullScreen = false,
  });

  /// Optional floor on the sheet height as a fraction of the screen height
  /// (e.g. 0.5): the sheet opens at least this tall even when its content is
  /// shorter, with the [footer] pinned to its bottom edge. Still capped by
  /// [maxHeightFraction] and the top safe area; content scrolls inside.
  final double? minHeightFraction;

  /// Cover the whole screen: no floating inset, no rounded corners, an
  /// opaque surface (the map is hidden behind it), and the top safe-area
  /// inset applied as padding inside the sheet. The [footer] pins to the
  /// bottom. Used for the ride-complete page.
  final bool fullScreen;

  /// Makes the grab handle a control: a 48-tall button (the touch floor)
  /// that the owner uses to expand / collapse a draggable sheet.
  /// [handleLabel] is what a screen reader says ("Expand" / "Collapse").
  /// Dragging is the owner's job (it wraps the sheet in its own vertical
  /// drag and drives [height]); the handle only takes the tap.
  final VoidCallback? onHandleTap;
  final String? handleLabel;

  /// An exact height in logical pixels, overriding [minHeightFraction] and
  /// [maxHeightFraction] (still kept below the status bar): set by a
  /// draggable sheet while it is dragged or snapping between its sizes.
  /// Null: the sheet sizes itself from the fractions and its content.
  final double? height;

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
    if (AppGlass.enabled) return _sized(context, media, _glass(context, media));
    return _sized(
      context,
      media,
      _SheetBody(
        isDark: isDark,
        padding: fullScreen
            ? padding.copyWith(top: padding.top + media.padding.top)
            : padding,
        handle: handle && !fullScreen,
        footer: footer,
        square: fullScreen,
        onHandleTap: onHandleTap,
        handleLabel: handleLabel,
        child: child,
      ),
    );
  }

  /// Applies the height range. The floor animates, so a sheet that is told
  /// to be taller (half-screen ride options, the full-screen ride-complete
  /// page) grows into it from wherever it was; under Reduce Motion it snaps.
  Widget _sized(BuildContext context, MediaQueryData media, Widget body) {
    final range = _heightConstraints(media);
    final exact = height;
    if (exact != null && !fullScreen) {
      final cap = media.size.height - media.padding.top - AppSpacing.md;
      final h = exact.clamp(0.0, cap < 0 ? 0.0 : cap);
      return SizedBox(height: h, child: body);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: range.minHeight),
      duration: AppMotion.of(context, AppMotion.slower),
      curve: AppMotion.standard,
      builder: (context, floor, child) => ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: floor < range.maxHeight ? floor : range.maxHeight,
          maxHeight: range.maxHeight,
        ),
        child: child,
      ),
      child: body,
    );
  }

  /// The sheet's height range: at most the screen minus the top safe area
  /// (or [maxHeightFraction] of it), at least [minHeightFraction] of it;
  /// exactly the screen when [fullScreen].
  BoxConstraints _heightConstraints(MediaQueryData media) {
    final screen = media.size.height;
    if (fullScreen) return BoxConstraints.tightFor(height: screen);
    var maxHeight = screen - media.padding.top - AppSpacing.md;
    final fraction = maxHeightFraction;
    if (fraction != null) {
      final capped = screen * fraction;
      if (capped < maxHeight) maxHeight = capped;
    }
    if (maxHeight < 0) maxHeight = 0;
    var minHeight = 0.0;
    final floor = minHeightFraction;
    if (floor != null) {
      minHeight = screen * floor;
      if (minHeight > maxHeight) minHeight = maxHeight;
    }
    return BoxConstraints(minHeight: minHeight, maxHeight: maxHeight);
  }
}

/// The sheet's inner column: the handle and the scrolling content on top,
/// the pinned footer at the bottom. When the sheet is held taller than its
/// content ([AppSheet.minHeightFraction], [AppSheet.fullScreen]) the spare
/// room goes between the two, so the footer stays on the bottom edge.
Widget _sheetColumn({
  required Widget? handle,
  required Widget content,
  required Widget? footer,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ?handle,
            Flexible(child: content),
          ],
        ),
      ),
      if (footer != null)
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.md),
            footer,
          ],
        ),
    ],
  );
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
    final bottomGap = media.padding.bottom > inset
        ? media.padding.bottom
        : inset;
    final content = MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: _FadeWhenMore(child: child),
    );
    // Full screen: the card's float and corners melt away and the safe-area
    // top becomes padding, so the card turns into the page.
    final margin = fullScreen
        ? EdgeInsets.zero
        : EdgeInsets.fromLTRB(inset, 0, inset, bottomGap);
    final duration = AppMotion.of(context, AppMotion.slow);
    return AnimatedPadding(
      duration: duration,
      curve: AppMotion.standard,
      padding: margin,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: chromeless ? 0 : 1),
        duration: duration,
        curve: AppMotion.standard,
        builder: (context, presence, content) => GlassSurface(
          strong: true,
          presence: presence,
          borderRadius: fullScreen
              ? BorderRadius.zero
              : const BorderRadius.all(Radius.circular(AppGlass.sheetRadius)),
          child: content!,
        ),
        child: AnimatedPadding(
          duration: duration,
          curve: AppMotion.standard,
          padding: chromeless
              ? EdgeInsets.zero
              : fullScreen
              ? EdgeInsets.fromLTRB(
                  side.left,
                  media.padding.top + side.top,
                  side.right,
                  bottomGap + side.bottom,
                )
              : EdgeInsets.fromLTRB(
                  side.left,
                  handle ? 0 : side.top,
                  side.right,
                  side.bottom,
                ),
          child: _sheetColumn(
            handle: handle && !chromeless && !fullScreen
                ? _GlassHandle(sheet: this)
                : null,
            content: content,
            footer: footer,
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
    Widget scroll = SingleChildScrollView(key: _scrollKey, child: widget.child);
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
/// floor). Drags are the sheet owner's (see [AppSheet.height]).
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
      container: true,
      button: true,
      label: sheet.handleLabel,
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: tap,
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
    this.square = false,
    this.onHandleTap,
    this.handleLabel,
  });

  final bool square;
  final VoidCallback? onHandleTap;
  final String? handleLabel;
  final bool isDark;
  final EdgeInsets padding;
  final bool handle;
  final Widget? footer;
  final Widget child;

  Widget _classicHandle() {
    final bar = Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          borderRadius: BorderRadius.circular(AppSpacing.pill),
        ),
      ),
    );
    final tap = onHandleTap;
    if (tap == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: bar,
      );
    }
    // A control: a 48-tall button (the touch floor) around the bar.
    return Semantics(
      container: true,
      button: true,
      label: handleLabel,
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: tap,
        child: SizedBox(height: 48, child: bar),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheet = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // Plan D: warm paper, so the white cards on it read as cards.
        color: AppVariant.local
            ? LocalColour.paperFor(isDark)
            : Theme.of(context).colorScheme.surface,
        borderRadius: square
            ? BorderRadius.zero
            : const BorderRadius.vertical(
                top: Radius.circular(AppSpacing.radiusXl),
              ),
        boxShadow: AppElevation.lg,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: _sheetColumn(
            handle: handle ? _classicHandle() : null,
            // Scroll the content when it can't fit the available height —
            // notably when the soft keyboard opens over a field in the sheet
            // (promo code, custom tip). Flexible + shrink-wrapping scroll view
            // keeps the sheet compact when content fits, and scrolls (instead
            // of overflowing) when it doesn't. The sheet is already laid out
            // below the top inset (see AppSheet.build), so inner scrollables
            // must not re-apply MediaQuery.padding.top as leading padding —
            // without this a ListView inside the sheet showed a phantom
            // status-bar-sized gap above its first row.
            content: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: SingleChildScrollView(child: child),
            ),
            footer: footer,
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
      ..arcToPoint(
        Offset(size.width - inset, r),
        radius: Radius.circular(r - inset),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          LocalColour.marigold.withValues(alpha: 0),
          LocalColour.marigold,
          LocalColour.marigold,
          LocalColour.marigold.withValues(alpha: 0),
        ],
        stops: const [0, 0.14, 0.86, 1],
      ).createShader(Offset.zero & Size(size.width, r));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MarigoldRulePainter old) =>
      old.radius != radius || old.width != width;
}
