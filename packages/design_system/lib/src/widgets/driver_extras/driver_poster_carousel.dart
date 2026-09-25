import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/phosphor_icons.dart';

/// One poster: a photo (or a colour wash) with a headline, a line of copy
/// and a call to action. Tapping it runs [onTap].
class DriverPoster {
  const DriverPoster({
    required this.title,
    required this.body,
    required this.cta,
    required this.icon,
    required this.onTap,
    this.image,
    this.tint = const Color(0xFF0E4D55),
  });

  final String title;
  final String body;
  final String cta;
  final IconData icon;
  final VoidCallback onTap;

  /// Asset path of a background photo; null draws a [tint] gradient.
  final String? image;
  final Color tint;
}

/// A horizontally swiped row of [DriverPoster]s (tips, announcements,
/// feature explainers) for the driver's pulled-up sheet. Its height follows
/// the text scale so 1.5x text still fits.
class DriverPosterCarousel extends StatefulWidget {
  const DriverPosterCarousel({super.key, required this.posters});

  final List<DriverPoster> posters;

  @override
  State<DriverPosterCarousel> createState() => _DriverPosterCarouselState();
}

class _DriverPosterCarouselState extends State<DriverPosterCarousel> {
  final _controller = PageController(viewportFraction: 0.9);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final height = 150 + 58 * (scale - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            itemCount: widget.posters.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _PosterCard(poster: widget.posters[i]),
            ),
          ),
        ),
        if (widget.posters.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.posters.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: i == _page ? 0.7 : 0.25),
                    borderRadius: BorderRadius.circular(AppSpacing.pill),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.poster});

  final DriverPoster poster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppSpacing.radiusLg);
    return Semantics(
      button: true,
      label: '${poster.title}. ${poster.body}. ${poster.cta}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: poster.tint,
          child: InkWell(
            onTap: poster.onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (poster.image != null)
                  Image.asset(
                    poster.image!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        poster.tint.withValues(alpha: 0.95),
                        poster.tint.withValues(
                            alpha: poster.image == null ? 0.75 : 0.35),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: -12,
                  bottom: -12,
                  child: Icon(poster.icon,
                      size: 96, color: Colors.white.withValues(alpha: 0.14)),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(poster.icon, size: 22, color: Colors.white),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        poster.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                        child: Text(
                          poster.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(poster.cta,
                              style: theme.textTheme.labelLarge
                                  ?.copyWith(color: Colors.white)),
                          const SizedBox(width: AppSpacing.xs),
                          const Icon(PhosphorIconsRegular.arrowRight,
                              size: 16, color: Colors.white),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
