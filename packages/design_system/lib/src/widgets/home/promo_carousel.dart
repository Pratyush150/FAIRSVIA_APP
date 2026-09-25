import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'promo_banner.dart';

/// A swipeable row of [PromoBanner] posters on the rider Home, one full-width
/// poster at a time, with page dots underneath.
///
/// It advances on its own every [interval] and loops back to the first
/// poster. Auto-advance stops while the rider's finger is on it (and restarts
/// the countdown after they let go), and is off entirely when the platform
/// asks for reduced motion or there is only one poster — swiping still works.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel(
    this.posters, {
    super.key,
    this.interval = const Duration(seconds: 5),
    this.autoAdvance = true,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  final List<PromoBannerData> posters;
  final Duration interval;
  final bool autoAdvance;
  final EdgeInsets padding;

  /// Diameter of an inactive dot; the active one stretches to [dotActiveW].
  static const double dotSize = 7;
  static const double dotActiveW = 20;

  /// How long one page turn takes.
  static const Duration turn = Duration(milliseconds: 450);

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final PageController _pages = PageController();
  Timer? _timer;
  int _index = 0;
  bool _held = false;

  bool get _canAuto {
    if (!widget.autoAdvance || widget.posters.length < 2 || _held) {
      return false;
    }
    if (!mounted) return false;
    return !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        TickerMode.valuesOf(context).enabled;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restart();
  }

  @override
  void didUpdateWidget(PromoCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= widget.posters.length) {
      _index = 0;
      if (_pages.hasClients) _pages.jumpToPage(0);
    }
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    if (_canAuto) _timer = Timer(widget.interval, _advance);
  }

  void _advance() {
    if (!mounted || !_pages.hasClients || widget.posters.length < 2) return;
    final next = (_index + 1) % widget.posters.length;
    // Looping back to the first poster jumps rather than rewinding past
    // every poster in between.
    if (next == 0) {
      _pages.jumpToPage(0);
    } else {
      _pages.animateToPage(
        next,
        duration: PromoCarousel.turn,
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _onPage(int i) {
    setState(() => _index = i);
    _restart();
  }

  void _hold(bool held) {
    _held = held;
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posters = widget.posters;
    if (posters.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = AppColors.inkFor(dark);
    final idle = active.withValues(alpha: 0.22);
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Listener(
            onPointerDown: (_) => _hold(true),
            onPointerUp: (_) => _hold(false),
            onPointerCancel: (_) => _hold(false),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: PageView.builder(
                controller: _pages,
                itemCount: posters.length,
                onPageChanged: _onPage,
                itemBuilder: (context, i) {
                  final p = posters[i];
                  return PromoBanner(
                    key: ValueKey(p.id),
                    headline: p.headline,
                    subline: p.subline,
                    art: p.art,
                    image: p.image,
                    tone: p.tone,
                    onTap: p.onTap,
                  );
                },
              ),
            ),
          ),
          if (posters.length > 1) ...[
            const SizedBox(height: AppSpacing.sm + 2),
            Semantics(
              label: 'Poster ${_index + 1} of ${posters.length}',
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < posters.length; i++)
                    AnimatedContainer(
                      key: ValueKey('promo-dot-$i'),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index
                          ? PromoCarousel.dotActiveW
                          : PromoCarousel.dotSize,
                      height: PromoCarousel.dotSize,
                      decoration: BoxDecoration(
                        color: i == _index ? active : idle,
                        borderRadius: BorderRadius.circular(
                          PromoCarousel.dotSize,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
