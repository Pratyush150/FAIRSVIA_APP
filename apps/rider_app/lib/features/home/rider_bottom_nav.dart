import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The rider's tabs. Home owns the map and the ride flow; the others are the
/// existing account pages, reachable in one tap.
enum RiderTab { home, trips, offers, account }

/// Bottom navigation for the idle Home only — it is hidden the moment the
/// rider starts booking, so the ride sheets keep the whole screen.
/// The active tab is full contrast; inactive ones use the muted icon token.
class RiderBottomNav extends StatelessWidget {
  const RiderBottomNav({
    super.key,
    required this.current,
    required this.onSelect,
  });

  final RiderTab current;
  final ValueChanged<RiderTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final active = theme.colorScheme.onSurface;
    final muted = AppColors.iconNeutralFor(dark);
    // Home, Trips and Account are Lottie line icons tinted at runtime with
    // the same selected / muted colours an Icon would get, so they follow any
    // theme colour. Each plays once when it appears (first show, and when its
    // tab is selected) and holds; Reduce Motion shows the finished icon.
    NavigationDestination dest(
      Widget Function(Key key, Color tint) icon,
      String name,
      String label,
    ) => NavigationDestination(
      icon: icon(ValueKey('nav-$name-idle'), muted),
      selectedIcon: icon(ValueKey('nav-$name-selected'), AppColors.accent),
      label: label,
    );
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: dark ? AppColors.surfaceDark : AppColors.surfaceLight,
        indicatorColor: AppColors.softFor(dark),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => theme.textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected) ? active : muted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: current.index,
        onDestinationSelected: (i) => onSelect(RiderTab.values[i]),
        destinations: [
          dest((k, c) => LottieMoment.navHome(key: k, tint: c), 'home', 'Home'),
          dest(
            (k, c) => LottieMoment.navTrips(key: k, tint: c),
            'trips',
            'Trips',
          ),
          // A small gift box drops in (twice, then holds) when the idle Home
          // shows and again when Offers is opened: noticeable, never a loop.
          // Reduce Motion shows the wrapped gift still.
          const NavigationDestination(
            icon: RiderOffersGift(key: ValueKey('offers-gift-idle')),
            selectedIcon: RiderOffersGift(
              key: ValueKey('offers-gift-selected'),
            ),
            label: 'Offers',
          ),
          dest(
            (k, c) => LottieMoment.navAccount(key: k, tint: c),
            'account',
            'Account',
          ),
        ],
      ),
    );
  }
}

/// The animated gift that stands in for the Offers tab icon (and heads the
/// Offers page). Plays [RiderOffersGift.plays] times then holds on the
/// wrapped gift.
class RiderOffersGift extends StatelessWidget {
  const RiderOffersGift({super.key, this.size = navSize});

  /// Drawn a touch larger than a 24 px icon: the art has air around it.
  static const double navSize = LottieMoment.navSize;
  static const int plays = 2;

  final double size;

  @override
  Widget build(BuildContext context) =>
      LottieMoment.gift(size: size, plays: plays);
}

/// The rider app's frame: the Home (map + ride flow) plus the other tabs,
/// with [RiderBottomNav] shown only while [showNav] (the idle Home).
///
/// Every tab lives in one IndexedStack so the Home's map is never torn down
/// when the rider looks at another tab. Other tabs are built the first time
/// they are opened, not up front. When [showNav] turns false (a ride has
/// started) the frame snaps back to Home, whatever tab was open.
class RiderTabScaffold extends StatefulWidget {
  const RiderTabScaffold({
    super.key,
    required this.home,
    required this.pages,
    required this.showNav,
    this.onTabChanged,
  });

  final Widget home;
  final Map<RiderTab, WidgetBuilder> pages;
  final bool showNav;
  final ValueChanged<RiderTab>? onTabChanged;

  /// Switches the enclosing frame back to Home (e.g. "Book a ride" on an
  /// empty Trips tab). No-op outside a [RiderTabScaffold].
  static void goHome(BuildContext context) => context
      .findAncestorStateOfType<_RiderTabScaffoldState>()
      ?._select(RiderTab.home);

  /// Switches the enclosing frame to [tab] (e.g. a Home poster opening
  /// Offers). No-op outside a [RiderTabScaffold].
  static void goTo(BuildContext context, RiderTab tab) =>
      context.findAncestorStateOfType<_RiderTabScaffoldState>()?._select(tab);

  @override
  State<RiderTabScaffold> createState() => _RiderTabScaffoldState();
}

class _RiderTabScaffoldState extends State<RiderTabScaffold> {
  RiderTab _tab = RiderTab.home;
  final Map<RiderTab, Widget> _built = {};

  @override
  void didUpdateWidget(RiderTabScaffold old) {
    super.didUpdateWidget(old);
    if (!widget.showNav && _tab != RiderTab.home) {
      _tab = RiderTab.home;
      widget.onTabChanged?.call(_tab);
    }
  }

  void _select(RiderTab tab) {
    if (tab == _tab) return;
    AppHaptics.selection();
    setState(() => _tab = tab);
    widget.onTabChanged?.call(tab);
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.showNav ? _tab : RiderTab.home;
    if (tab != RiderTab.home) {
      _built.putIfAbsent(tab, () => Builder(builder: widget.pages[tab]!));
    }
    return Scaffold(
      body: IndexedStack(
        index: tab.index,
        children: [
          for (final t in RiderTab.values)
            t == RiderTab.home
                ? widget.home
                : (_built[t] ?? const SizedBox.shrink()),
        ],
      ),
      bottomNavigationBar: widget.showNav
          ? RiderBottomNav(current: tab, onSelect: _select)
          : null,
    );
  }
}
