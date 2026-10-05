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

/// A full-width promo card on the rider Home, 16:10, radius 20, headline
/// top-left, optional subline, and a round arrow CTA bottom-right. The whole
/// card is the tap target and one button in the accessibility tree.
///
/// Two looks:
///  * **photo** — [image] (an asset path, e.g. [PromoPhoto.cityNight]) fills
///    the card under a dark left-to-right scrim ([scrimAlphaAt]) so the white
///    headline stays legible on any photo;
///  * **art** — a soft brand gradient with the 3D clay [art] at the right.
class PromoBanner extends StatelessWidget {
  const PromoBanner({
    super.key,
    required this.headline,
    this.subline,
    this.art,
    this.image,
    this.onTap,
    this.tone = PromoTone.teal,
  }) : assert(art != null || image != null, 'Give an art key or an image');

  final String headline;
  final String? subline;

  /// A [HomeArt] key (art look). Ignored when [image] is set.
  final String? art;

  /// A photo asset path (photo look); see [PromoPhoto].
  final String? image;
  final VoidCallback? onTap;
  final PromoTone tone;

  static const double radius = AppSpacing.radiusXl;
  static const double ctaSize = 48;

  /// Text colours on the photo look (always white on the dark scrim).
  static const Color photoHeadline = Color(0xFFFFFFFF);
  static const Color photoSubline = Color(0xE6FFFFFF);

  /// The scrim's colour: a near-black with a hint of the brand ink.
  static const Color scrimColor = Color(0xFF05100F);

  /// Scrim opacity stops across the card's width (left → right). Text never
  /// runs past [textWidthFraction] of the width, where the scrim is still
  /// ≥ [minTextScrimAlpha].
  static const List<double> scrimStops = [0, 0.62, 1];
  static const List<double> scrimAlphas = [0.74, 0.62, 0.12];

  /// The widest the text column gets, as a fraction of the card width.
  static const double textWidthFraction = 0.62;

  /// Scrim opacity at horizontal position [t] (0 = left edge, 1 = right).
  static double scrimAlphaAt(double t) {
    for (var i = 1; i < scrimStops.length; i++) {
      if (t <= scrimStops[i]) {
        final f = (t - scrimStops[i - 1]) / (scrimStops[i] - scrimStops[i - 1]);
        return scrimAlphas[i - 1] + (scrimAlphas[i] - scrimAlphas[i - 1]) * f;
      }
    }
    return scrimAlphas.last;
  }

  /// The lowest scrim opacity anywhere behind the text.
  static double get minTextScrimAlpha => scrimAlphaAt(textWidthFraction);

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

  Widget _semantics({required Widget child}) => Semantics(
    // Only a button when it does something — a promo without an action is
    // read as text, not as a "disabled button" (audit).
    button: onTap != null,
    label: subline == null ? headline : '$headline. $subline',
    excludeSemantics: true,
    // The InkWell's tap is excluded with its subtree; expose it here so
    // screen-reader activation works.
    onTap: onTap,
    child: Builder(
      builder: (context) => PressScale(
        enabled: onTap != null,
        scale: 0.96,
        rim: true,
        glow: PressScale.brandGlow(
          Theme.of(context).brightness == Brightness.dark,
        ),
        glowRadius: BorderRadius.circular(radius),
        child: AspectRatio(aspectRatio: 16 / 10, child: child),
      ),
    ),
  );

  /// Headline + subline, sized for the text scale (shared by both looks).
  Widget _text(BuildContext context, Color primary, Color secondary) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headline,
          // Two lines; a third only at large text sizes, where cutting the
          // headline off would hide the offer from the readers who raised
          // the size.
          maxLines: MediaQuery.textScalerOf(context).scale(10) > 11.5 ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: primary,
          ),
        ),
        if (subline != null) ...[
          const SizedBox(height: AppSpacing.xs + 2),
          Flexible(
            // As many whole lines (≤ 2) as fit — never a line sliced in half
            // at large text sizes.
            child: LayoutBuilder(
              builder: (context, box) {
                final style = theme.textTheme.bodyMedium?.copyWith(
                  color: secondary,
                );
                final fs = style?.fontSize ?? 15;
                final line =
                    MediaQuery.textScalerOf(context).scale(fs) *
                    (style?.height ?? 1.4);
                final lines = (box.maxHeight / line).floor().clamp(0, 2);
                if (lines == 0) return const SizedBox.shrink();
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
    );
  }

  @override
  Widget build(BuildContext context) =>
      image != null ? _buildPhoto(context) : _buildArt(context);

  Widget _buildPhoto(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    return _semantics(
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: r,
            color: scrimColor,
            border: Border.all(color: HomeSurface.rim(dark)),
          ),
          child: ClipRRect(
            borderRadius: r,
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final dpr = MediaQuery.devicePixelRatioOf(context);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      image!,
                      fit: BoxFit.cover,
                      // Decode at the drawn size, not the file's 1200 px.
                      cacheWidth: w.isFinite ? (w * dpr).round() : null,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            for (final a in scrimAlphas)
                              scrimColor.withValues(alpha: a),
                          ],
                          stops: scrimStops,
                        ),
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.x20,
                      top: AppSpacing.x20,
                      bottom: AppSpacing.x20,
                      width: w * textWidthFraction - AppSpacing.x20,
                      child: _text(context, photoHeadline, photoSubline),
                    ),
                    const Positioned(
                      right: AppSpacing.lg,
                      bottom: AppSpacing.lg,
                      // Light disc, dark arrow: reads on any photo.
                      child: _Cta(dark: true, onPhoto: true),
                    ),
                    const PosterShimmer(),
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(onTap: onTap, borderRadius: r),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArt(BuildContext context) {
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

    return _semantics(
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
                        child: HomeArtImage(art!, size: artSize),
                      ),
                      Positioned(
                        left: AppSpacing.x20,
                        top: AppSpacing.x20,
                        bottom: AppSpacing.x20,
                        width: textW,
                        child: _text(context, primary, secondary),
                      ),
                      Positioned(
                        right: AppSpacing.lg,
                        bottom: AppSpacing.lg,
                        child: _Cta(dark: dark),
                      ),
                      const PosterShimmer(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A light diagonal glint that sweeps across a poster every [period]
/// (the sweep itself takes [sweep]; the rest of the period is still).
///
/// Painted only: a [CustomPaint] driven by the controller (`repaint:`), in
/// its own [RepaintBoundary], so the image, text and art under it are never
/// rebuilt or repainted. Fills its [Stack]; ignores pointers; hidden from
/// screen readers. Static (draws nothing) under Reduce Motion or when
/// [debugDisableLoops] is set (tests, so `pumpAndSettle` settles); paused
/// with the ticker when its route or tab is offstage ([TickerMode]).
class PosterShimmer extends StatefulWidget {
  const PosterShimmer({super.key});

  /// One full cycle: a sweep, then a rest.
  static const Duration period = Duration(seconds: 6);

  /// How long the glint takes to cross the poster.
  static const Duration sweep = Duration(milliseconds: 1100);

  /// Peak white alpha at the centre of the glint.
  static const double peakAlpha = 0.26;

  /// Set in tests (see test/flutter_test_config.dart) so the endless loop
  /// never keeps `pumpAndSettle` from settling.
  static bool debugDisableLoops = false;

  @override
  State<PosterShimmer> createState() => _PosterShimmerState();
}

class _PosterShimmerState extends State<PosterShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: PosterShimmer.period,
  );
  bool _still = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        PosterShimmer.debugDisableLoops;
    if (_still) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_still) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: RepaintBoundary(
            child: CustomPaint(painter: _ShimmerPainter(_c)),
          ),
        ),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final frac =
        PosterShimmer.sweep.inMicroseconds /
        PosterShimmer.period.inMicroseconds;
    final p = t.value / frac;
    if (p <= 0 || p >= 1) return; // resting between sweeps
    final eased = Curves.easeInOut.transform(p);
    // A band ~35% of the width, travelling from fully off the left edge to
    // fully off the right, tilted ~20 degrees.
    final band = size.width * 0.35;
    final x = -band + (size.width + band * 2) * eased;
    final rect = Rect.fromLTWH(x - band, 0, band * 2, size.height);
    const peak = PosterShimmer.peakAlpha;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-1, -0.35),
        end: const Alignment(1, 0.35),
        colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: peak),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0.3, 0.5, 0.7],
      ).createShader(rect);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t;
}

class _Cta extends StatelessWidget {
  const _Cta({required this.dark, this.onPhoto = false});

  final bool dark;

  /// On a photo: a white disc with a black arrow in every theme.
  final bool onPhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: PromoBanner.ctaSize,
      height: PromoBanner.ctaSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: onPhoto ? AppColors.white : AppColors.inkFor(dark),
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
        color: onPhoto ? AppColors.black : AppColors.onInkFor(dark),
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
    this.art,
    this.image,
    this.tone = PromoTone.teal,
    this.onTap,
  }) : assert(art != null || image != null, 'Give an art key or an image');

  /// Stable id (list key, analytics).
  final String id;
  final String headline;
  final String? subline;

  /// A [HomeArt] key (art look).
  final String? art;

  /// A photo asset path (photo look, wins over [art]); see [PromoPhoto].
  final String? image;
  final PromoTone tone;
  final VoidCallback? onTap;

  PromoBannerData copyWith({VoidCallback? onTap}) => PromoBannerData(
    id: id,
    headline: headline,
    subline: subline,
    art: art,
    image: image,
    tone: tone,
    onTap: onTap ?? this.onTap,
  );
}

/// Bundled promo pictures. FAIRSVIA's shipped look (the glass build) uses its
/// own flat illustrations in the brand blue + coral (assets/promo_fairsvia/,
/// drawn by tools/brand/build_posters.mjs); every other build keeps the
/// photos (Unsplash License; assets/promo/CREDITS.md). Same file names and
/// 1200x750 size, so callers do not change. Generic scenes — no city names,
/// landmarks, logos or legible number plates, so they suit any launch market.
/// The per-image notes below describe the photos.
abstract final class PromoPhoto {
  static const String _dir = AppColors.glass
      ? 'packages/design_system/assets/promo_fairsvia'
      : 'packages/design_system/assets/promo';

  /// A taxi moving through the city at night (motion blur).
  static const String cityNight = '$_dir/city_night.jpg';

  /// A minivan at an airport terminal drop-off.
  static const String airport = '$_dir/airport.jpg';

  /// A white sedan on a city street by day (motion blur).
  static const String cityDay = '$_dir/city_day.jpg';

  static const List<String> all = [cityNight, airport, cityDay];

  // Home poster carousel (webp, 1200x750).

  /// Light trails along an empty road at night.
  static const String offersNight = '$_dir/offers_night.webp';

  /// A city's highways lighting up at dusk, seen from above.
  static const String scheduleDusk = '$_dir/schedule_dusk.webp';

  /// A rider's view from the back seat at night.
  static const String safetyRide = '$_dir/safety_ride.webp';

  /// A passenger in the back seat of a car.
  static const String shareTrip = '$_dir/share_trip.webp';

  static const List<String> posters = [
    offersNight,
    scheduleDusk,
    safetyRide,
    shareTrip,
  ];
}

/// Placeholder promos for the Home until a promos API exists. Neutral,
/// market-agnostic copy: no city names, prices, discounts or claims the
/// product does not back.
const List<PromoBannerData> kMockPromos = [
  PromoBannerData(
    id: 'ride-anywhere',
    headline: 'Ride anywhere in the city',
    subline: 'See the fare before you book.',
    image: PromoPhoto.cityNight,
    art: HomeArt.ride,
  ),
  PromoBannerData(
    id: 'prebook-airport',
    headline: 'Book your airport ride ahead',
    subline: 'Choose your pickup time in advance.',
    image: PromoPhoto.airport,
    art: HomeArt.prebook,
    tone: PromoTone.mint,
  ),
  PromoBannerData(
    id: 'add-a-stop',
    headline: 'Add a stop, see the price first',
    subline: 'The fare updates before you confirm.',
    image: PromoPhoto.cityDay,
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
              image: promos[i].image,
              tone: promos[i].tone,
              onTap: promos[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}
