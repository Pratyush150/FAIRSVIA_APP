import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../layout/rider_sheet_heights.dart';
import 'home_data.dart';

/// How far the sheet's rounded top overlaps the bottom of the map header.
const double kHomeSheetOverlap = 24;

/// Height of the pinned search header: sheet top padding + 56 dp field +
/// bottom gap.
const double _searchHeaderExtent = AppSpacing.lg + 56 + AppSpacing.md;

/// The idle Home, drawn OVER the full-screen map the rest of the ride flow
/// uses (so the map is never torn down and rebuilt when booking starts):
///
/// * a transparent window on the top of the screen
///   ([RiderSheetHeights.homeMap]) — touches there fall
///   through to the map, so it still pans and zooms;
/// * a solid sheet (24 dp top radius) that scrolls up over the map; its
///   search bar pins to the top, so scrolling "collapses" the map header;
/// * floating glass controls on the map (menu, current address + heart,
///   recenter) that fade out as the sheet covers the map.
class IdleHome extends StatefulWidget {
  const IdleHome({
    super.key,
    required this.searchBar,
    required this.sections,
    required this.onMenu,
    required this.onRecenter,
    required this.addressLabel,
    required this.isSaved,
    required this.onToggleSaved,
    this.banners,
    this.bannersVisible = false,
  });

  /// The pinned hero (HomeSearchBar, or the location gate).
  final Widget searchBar;

  /// Everything under the search bar, top to bottom.
  final List<Widget> sections;

  final VoidCallback onMenu;
  final VoidCallback onRecenter;

  /// Short current address for the chip; null hides the chip.
  final String? addressLabel;
  final bool isSaved;

  /// Null disables the heart (no real location to save yet).
  final VoidCallback? onToggleSaved;

  /// Connection / location banners, drawn above the controls.
  final Widget? banners;
  final bool bannersVisible;

  /// Height of the map window for a screen of [screenHeight].
  static double headerHeightFor(double screenHeight) =>
      screenHeight * RiderSheetHeights.current.homeMap;

  @override
  State<IdleHome> createState() => _IdleHomeState();
}

class _IdleHomeState extends State<IdleHome> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double get _offset => _scroll.hasClients ? _scroll.offset : 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final header = IdleHome.headerHeightFor(media.size.height);
    // The part of the header the scroll view leaves see-through (it sits
    // inside the top safe area inset, which is outside the scroll view).
    final window = (header - media.padding.top - kHomeSheetOverlap).clamp(
      0.0,
      double.infinity,
    );
    final sheet = dark ? AppColors.backgroundDark : AppColors.backgroundLight;
    return Stack(
      children: [
        Positioned.fill(
          child: SafeArea(
            bottom: false,
            child: _PassThroughAbove(
              // Touches above the sheet's current top edge reach the map.
              edge: () => window - _offset,
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: window)),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SearchHeader(
                      color: sheet,
                      child: widget.searchBar,
                    ),
                  ),
                  DecoratedSliver(
                    decoration: BoxDecoration(color: sheet),
                    sliver: SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        0,
                        AppSpacing.xs,
                        0,
                        0,
                      ),
                      sliver: SliverList.list(
                        children: [
                          for (final s in widget.sections) ...[
                            s,
                            const SizedBox(height: AppSpacing.lg),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ColoredBox(
                      color: sheet,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Floating controls over the map; they fade as the sheet covers it.
        Positioned.fill(
          child: ListenableBuilder(
            listenable: _scroll,
            builder: (context, _) {
              final fade =
                  (1 - _offset / (window * 0.6).clamp(1.0, double.infinity))
                      .clamp(0.0, 1.0);
              return Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ?widget.banners,
                        SafeArea(
                          top: !widget.bannersVisible,
                          bottom: false,
                          child: _fading(
                            fade,
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: _TopControls(
                                onMenu: widget.onMenu,
                                addressLabel: widget.addressLabel,
                                isSaved: widget.isSaved,
                                onToggleSaved: widget.onToggleSaved,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: AppSpacing.lg,
                    top:
                        media.padding.top +
                        window -
                        _offset -
                        48 -
                        AppSpacing.md,
                    child: _fading(
                      fade,
                      AppCircleButton(
                        icon: PhosphorIconsRegular.gpsFix,
                        tooltip: 'Recenter on my location',
                        onPressed: widget.onRecenter,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static Widget _fading(double fade, Widget child) => IgnorePointer(
    ignoring: fade < 0.5,
    child: Opacity(opacity: fade, child: child),
  );
}

/// Menu disc on the left; the current-address chip with its heart on the
/// right.
class _TopControls extends StatelessWidget {
  const _TopControls({
    required this.onMenu,
    required this.addressLabel,
    required this.isSaved,
    required this.onToggleSaved,
  });

  final VoidCallback onMenu;
  final String? addressLabel;
  final bool isSaved;
  final VoidCallback? onToggleSaved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = addressLabel;
    return Row(
      children: [
        AppCircleButton(
          icon: PhosphorIconsRegular.list,
          tooltip: 'Account menu',
          onPressed: onMenu,
        ),
        const SizedBox(width: AppSpacing.md),
        const Spacer(),
        if (label != null)
          Flexible(
            flex: 6,
            child: GlassSurface(
              strong: true,
              borderRadius: BorderRadius.circular(AppSpacing.pill),
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.lg),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: isSaved ? 'Saved place' : 'Save this place',
                      onPressed: onToggleSaved,
                      icon: Icon(
                        isSaved
                            ? PhosphorIconsFill.heart
                            : PhosphorIconsRegular.heart,
                        color: isSaved
                            ? AppColors.accent
                            : theme.colorScheme.onSurface,
                        size: AppIconSize.row,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The sheet's rounded, slightly raised top edge carrying the search bar.
/// Pinned: once the sheet has scrolled up, it stays at the top of the screen.
class _SearchHeader extends SliverPersistentHeaderDelegate {
  _SearchHeader({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  double get minExtent => _searchHeaderExtent;
  @override
  double get maxExtent => _searchHeaderExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(kHomeSheetOverlap),
        ),
        boxShadow: AppElevation.float,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Align(alignment: Alignment.topCenter, child: child),
      ),
    );
  }

  @override
  bool shouldRebuild(_SearchHeader old) =>
      old.color != color || old.child != child;
}

/// "Recent" — the last few drop-offs, each one tap from booking.
class RecentDestinationsCard extends StatelessWidget {
  const RecentDestinationsCard({
    super.key,
    required this.items,
    required this.onPick,
  });

  final List<RecentDestination> items;
  final ValueChanged<RecentDestination> onPick;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = AppColors.iconNeutralFor(dark);
    return HomeCard(
      child: Column(
        children: [
          for (final r in items) ...[
            InkWell(
              onTap: () => onPick(r),
              child: Semantics(
                button: true,
                label: 'Ride to ${r.address}',
                excludeSemantics: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          PhosphorIconsRegular.clock,
                          color: muted,
                          size: AppIconSize.row,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Icon(
                          PhosphorIconsRegular.caretRight,
                          color: muted,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (r != items.last)
              Divider(
                height: 1,
                indent: AppSpacing.lg + AppIconSize.row + AppSpacing.md,
                color: theme.dividerColor,
              ),
          ],
        ],
      ),
    );
  }
}

/// A card on the Home sheet: one step lighter than the sheet behind it, so
/// cards separate from the page in dark mode too.
class HomeCard extends StatelessWidget {
  const HomeCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Lets hits above [edge] (in local coordinates) fall through to whatever is
/// under this widget — the map, on the Home.
class _PassThroughAbove extends SingleChildRenderObjectWidget {
  const _PassThroughAbove({required this.edge, super.child});

  final double Function() edge;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPassThroughAbove(edge);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPassThroughAbove renderObject,
  ) {
    renderObject.edge = edge;
  }
}

class _RenderPassThroughAbove extends RenderProxyBox {
  _RenderPassThroughAbove(this.edge);

  double Function() edge;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (position.dy < edge()) return false;
    return super.hitTest(result, position: position);
  }
}
