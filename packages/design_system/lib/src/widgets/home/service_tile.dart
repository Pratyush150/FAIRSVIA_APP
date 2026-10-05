import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'home_art.dart';
import 'press_scale.dart';

/// One service on the rider Home ("Ride", "Pre-book", …): a ~100×100 card,
/// a step lighter than the page, with a 3D clay illustration over a one-line
/// label. [art] is a [HomeArt] key. [badge] is an optional short tag
/// ("New", "Promo") pinned to the top-right corner.
///
/// Grows taller (never clips) when the system text size is raised; see
/// [heightFor].
class ServiceTile extends StatelessWidget {
  const ServiceTile({
    super.key,
    required this.label,
    required this.art,
    this.onTap,
    this.badge,
    this.width = defaultWidth,
    this.semanticLabel,
    this.wide = false,
  });

  final String label;
  final String art;
  final VoidCallback? onTap;
  final String? badge;

  /// Tile width (default 100).
  final double width;

  /// Overrides the spoken label (defaults to "[label], [badge]").
  final String? semanticLabel;

  /// FAIRSVIA's grid tile: the art on the left and the label beside it, in a
  /// short, wide card (see [ServicesRow.grid]). The square tile otherwise.
  final bool wide;

  static const double wideArtSize = 44;

  /// The wide tile's height: 64 at 1.0 text scale, taller as the label grows.
  static double wideHeightFor(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final size = style?.fontSize ?? 14;
    final line = size * (style?.height ?? 20 / 14);
    final scaled = MediaQuery.textScalerOf(context).scale(size) / size * line;
    return math.max(64, (scaled + 2 * AppSpacing.md).ceilToDouble());
  }

  static const double defaultWidth = 100;
  static const double artSize = 56;
  static const double _padTop = 10;
  static const double _gap = 6;
  static const double _padBottom = 10;

  /// The tile's height for the ambient text scale: 100 at 1.0, taller as the
  /// label's line grows.
  static double heightFor(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium;
    final size = style?.fontSize ?? 14;
    final line = size * (style?.height ?? 18 / 14);
    final scaled = MediaQuery.textScalerOf(context).scale(size) / size * line;
    return (_padTop + artSize + _gap + scaled + _padBottom).ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(HomeSurface.radius);
    final height = wide ? wideHeightFor(context) : heightFor(context);

    final body = wide
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                HomeArtImage(art, size: wideArtSize),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          )
        : Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        _padTop,
        AppSpacing.sm,
        _padBottom,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Flexible: a font whose line box runs a pixel or two taller than
          // the token's 18 shrinks the art slightly instead of overflowing.
          Flexible(
            child: FittedBox(child: HomeArtImage(art, size: artSize)),
          ),
          const SizedBox(height: _gap),
          // Large text: the label shrinks to fit the tile rather than being
          // cut to "Saved p…" (audit #32).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel ?? (badge == null ? label : '$label, $badge'),
      excludeSemantics: true,
      // The InkWell's tap is excluded with its subtree; expose it here so
      // screen-reader activation works.
      onTap: onTap,
      child: PressScale(
        enabled: onTap != null,
        rim: true,
        glow: PressScale.brandGlow(dark),
        glowRadius: radius,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: HomeSurface.decoration(dark),
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: radius,
                      child: body,
                    ),
                  ),
                ),
              ),
              if (badge != null)
                Positioned(
                  top: AppSpacing.xs + 2,
                  right: AppSpacing.xs + 2,
                  child: IgnorePointer(child: _Badge(badge!, dark: dark)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.dark});

  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm - 2,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.inkFor(dark),
        borderRadius: BorderRadius.circular(AppSpacing.pill),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.onInkFor(dark),
          fontWeight: FontWeight.w700,
          fontSize: 10,
          height: 14 / 10,
        ),
      ),
    );
  }
}

/// One entry of a [ServicesRow].
@immutable
class ServiceItem {
  const ServiceItem(this.label, this.art, this.onTap, {this.badge});

  final String label;

  /// A [HomeArt] key.
  final String art;
  final VoidCallback? onTap;
  final String? badge;
}

/// The Home services: [ServiceTile]s with 16 dp side padding and 12 dp gaps.
/// FAIRSVIA's shipped look ([grid], the glass build) lays them out as a
/// two-column grid of wide tiles, so its Home is recognisably its own next
/// to RideVela's. Other builds keep the horizontal strip, which scrolls
/// sideways when the tiles outgrow the screen (a 360 dp phone shows three and
/// a half — the cue that there is more).
class ServicesRow extends StatelessWidget {
  const ServicesRow({
    super.key,
    required this.items,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  final List<ServiceItem> items;
  final EdgeInsets padding;

  /// Two-column grid of wide tiles instead of the scrolling strip.
  static const bool grid = AppColors.glass;

  @override
  Widget build(BuildContext context) {
    if (grid) {
      return Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = ((c.maxWidth - AppSpacing.md) / 2).floorToDouble();
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final it in items)
                  ServiceTile(
                    label: it.label,
                    art: it.art,
                    onTap: it.onTap,
                    badge: it.badge,
                    width: w,
                    wide: true,
                  ),
              ],
            );
          },
        ),
      );
    }
    return SizedBox(
      height: ServiceTile.heightFor(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, i) {
          final it = items[i];
          return ServiceTile(
            label: it.label,
            art: it.art,
            onTap: it.onTap,
            badge: it.badge,
          );
        },
      ),
    );
  }
}
