import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/phosphor_icons.dart';
import 'home_art.dart';
import 'press_scale.dart';

/// The brand tint a [PromoBanner]'s gradient is mixed from.
enum PromoTone {
  /// Brand turquoise (default).
  teal,

  /// Warm: the star gold over the brand soft fill.
  sun,

  /// Green-teal: the success green over the brand soft fill.
  mint,
}

/// A full-width promo card on the rider Home: soft brand gradient, a 3D clay
/// illustration at the right, headline top-left, optional subline, and a
/// round arrow CTA bottom-right. 16:10, radius 20. The whole card is the
/// tap target and one button in the accessibility tree.
class PromoBanner extends StatelessWidget {
  const PromoBanner({
    super.key,
    required this.headline,
    this.subline,
    required this.art,
    this.onTap,
    this.tone = PromoTone.teal,
  });

  final String headline;
  final String? subline;

  /// A [HomeArt] key.
  final String art;
  final VoidCallback? onTap;
  final PromoTone tone;

  static const double radius = AppSpacing.radiusXl;
  static const double ctaSize = 48;

  static (Color, Color, Color) _palette(PromoTone tone, bool dark) {
    final soft = AppColors.softFor(dark);
    final base = dark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final tint = switch (tone) {
      PromoTone.teal => AppColors.highlightFor(dark),
      PromoTone.sun => AppColors.star,
      PromoTone.mint => AppColors.success,
    };
    // Top-left stays close to the page so the headline has calm contrast;
    // the bottom-right warms into the tint behind the art.
    final start = Color.alphaBlend(
      tint.withValues(alpha: dark ? 0.06 : 0.05),
      dark ? base : soft,
    );
    final end = Color.alphaBlend(
      tint.withValues(alpha: dark ? 0.26 : 0.30),
      dark ? soft : soft,
    );
    final glow = tint.withValues(alpha: dark ? 0.30 : 0.34);
    return (start, end, glow);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final (start, end, glow) = _palette(tone, dark);
    final r = BorderRadius.circular(radius);
    final primary = dark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;
    final secondary = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: subline == null ? headline : '$headline. $subline',
      excludeSemantics: true,
      // The InkWell's tap is excluded with its subtree; expose it here so
      // screen-reader activation works.
      onTap: onTap,
      child: PressScale(
        enabled: onTap != null,
        scale: 0.98,
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: r,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [start, end],
                ),
                border: Border.all(color: HomeSurface.rim(dark)),
              ),
              child: InkWell(
                onTap: onTap,
                borderRadius: r,
                child: ClipRRect(
                  borderRadius: r,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth, h = c.maxHeight;
                      final artSize = (h * 0.56).clamp(72.0, 180.0);
                      // Text stops short of the art so they never overlap.
                      final textW =
                          (w -
                                  artSize -
                                  AppSpacing.md -
                                  AppSpacing.x20 -
                                  AppSpacing.xs)
                              .clamp(w * 0.5, w * 0.6);
                      return Stack(
                        children: [
                          // Soft glow the art sits in.
                          Positioned(
                            right: -h * 0.18,
                            top: -h * 0.10,
                            width: h * 1.05,
                            height: h * 1.05,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [glow, glow.withValues(alpha: 0)],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: AppSpacing.md,
                            top: AppSpacing.md,
                            child: HomeArtImage(art, size: artSize),
                          ),
                          Positioned(
                            left: AppSpacing.x20,
                            top: AppSpacing.x20,
                            bottom: AppSpacing.x20,
                            width: textW,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  headline,
                                  // Two lines; a third only at large text
                                  // sizes, where cutting the headline off
                                  // would hide the offer from the readers who
                                  // raised the size.
                                  maxLines:
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(10) >
                                          11.5
                                      ? 3
                                      : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: primary,
                                  ),
                                ),
                                if (subline != null) ...[
                                  const SizedBox(height: AppSpacing.xs + 2),
                                  Flexible(
                                    // As many whole lines (≤ 2) as fit —
                                    // never a line sliced in half at large
                                    // text sizes.
                                    child: LayoutBuilder(
                                      builder: (context, box) {
                                        final style = theme.textTheme.bodyMedium
                                            ?.copyWith(color: secondary);
                                        final fs = style?.fontSize ?? 15;
                                        final line =
                                            MediaQuery.textScalerOf(
                                              context,
                                            ).scale(fs) *
                                            (style?.height ?? 1.4);
                                        final lines = (box.maxHeight / line)
                                            .floor()
                                            .clamp(0, 2);
                                        if (lines == 0) {
                                          return const SizedBox.shrink();
                                        }
                                        return Text(
                                          subline!,
                                          maxLines: lines,
                                          overflow: TextOverflow.ellipsis,
                                          style: style,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Positioned(
                            right: AppSpacing.lg,
                            bottom: AppSpacing.lg,
                            child: _Cta(dark: dark),
                          ),
                        ],
                      );
                    },
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

class _Cta extends StatelessWidget {
  const _Cta({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: PromoBanner.ctaSize,
      height: PromoBanner.ctaSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.inkFor(dark),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: dark ? 0.35 : 0.14),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        PhosphorIconsRegular.arrowRight,
        size: 22,
        color: AppColors.onInkFor(dark),
      ),
    );
  }
}

/// Data for one [PromoBanner].
@immutable
class PromoBannerData {
  const PromoBannerData({
    required this.id,
    required this.headline,
    this.subline,
    required this.art,
    this.tone = PromoTone.teal,
    this.onTap,
  });

  /// Stable id (list key, analytics).
  final String id;
  final String headline;
  final String? subline;

  /// A [HomeArt] key.
  final String art;
  final PromoTone tone;
  final VoidCallback? onTap;

  PromoBannerData copyWith({VoidCallback? onTap}) => PromoBannerData(
    id: id,
    headline: headline,
    subline: subline,
    art: art,
    tone: tone,
    onTap: onTap ?? this.onTap,
  );
}

/// Placeholder promos for the Home until a promos API exists. Neutral copy:
/// no prices, discounts or claims the product does not back.
const List<PromoBannerData> kMockPromos = [
  PromoBannerData(
    id: 'ride-for-less',
    headline: 'Ride across Pune for less',
    subline: 'See the fare before you book.',
    art: HomeArt.ride,
  ),
  PromoBannerData(
    id: 'prebook-airport',
    headline: 'Pre-book your airport ride',
    subline: 'Choose your pickup time in advance.',
    art: HomeArt.prebook,
    tone: PromoTone.mint,
  ),
  PromoBannerData(
    id: 'add-a-stop',
    headline: 'Add a stop, see the price first',
    subline: 'The fare updates before you confirm.',
    art: HomeArt.addStop,
    tone: PromoTone.sun,
  ),
];

/// [PromoBanner]s stacked vertically with 12 dp gaps. Not scrollable itself:
/// it lays out inside the Home's own scroll view.
class PromoBannerList extends StatelessWidget {
  const PromoBannerList(
    this.promos, {
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  final List<PromoBannerData> promos;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < promos.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            PromoBanner(
              key: ValueKey(promos[i].id),
              headline: promos[i].headline,
              subline: promos[i].subline,
              art: promos[i].art,
              tone: promos[i].tone,
              onTap: promos[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}
