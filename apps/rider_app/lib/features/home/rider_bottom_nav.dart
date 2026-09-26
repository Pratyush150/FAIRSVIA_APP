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

  /// Opacity of the unselected tabs' illustrations.
  static const double idleOpacity = 0.6;

  /// Idle opacity on the dark bar: higher so the house stays readable.
  static const double idleOpacityDark = 0.75;

  final RiderTab current;
  final ValueChanged<RiderTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final active = theme.colorScheme.onSurface;
    final muted = AppColors.iconNeutralFor(dark);
    // All four tabs are colourful Lottie illustrations in the brand palette
    // (house, car, gift, user). Each plays [LottieMoment.navPlays] times when
    // it appears (first show, and each time its tab is selected) and holds;
    // Reduce Motion shows the finished frame. The selected tab is full colour
    // in the pill; the others sit at [idleOpacity] so the active one leads.
    // Home, Trips and Account also get a one-shot pop (the gift already
    // drops in by itself) so the entrance reads clearly on a phone.
    Widget pop(String name, String state, Widget child) => name == 'offers'
        ? child
        : NavPop(
            key: ValueKey('pop-$name-$state'),
            slideIn: name == 'trips',
            child: child,
          );
    NavigationDestination dest(
      Widget Function(Key key) icon,
      String name,
      String label,
    ) => NavigationDestination(
      icon: Opacity(
        opacity: dark ? idleOpacityDark : idleOpacity,
        child: pop(name, 'idle', icon(ValueKey('nav-$name-idle'))),
      ),
      selectedIcon: pop(name, 'selected', icon(ValueKey('nav-$name-selected'))),
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
          dest((k) => LottieMoment.navHome(key: k), 'home', 'Home'),
          dest((k) => LottieMoment.navTrips(key: k), 'trips', 'Trips'),
          dest((k) => RiderOffersGift(key: k), 'offers', 'Offers'),
          dest((k) => LottieMoment.navAccount(key: k), 'account', 'Account'),
        ],
      ),
    );
  }
}

/// A one-shot entrance for a nav icon: it pops (0.55 -> 1.18 -> 1.0) with
/// a small upward hop, and with [slideIn] also slides in from the left.
/// Runs once when the icon is built (first show, and each time its tab is
/// selected, since the selected icon is a new widget). None under Reduce
/// Motion.
class NavPop extends StatefulWidget {
  const NavPop({super.key, required this.child, this.slideIn = false});

  static const Duration duration = Duration(milliseconds: 500);

  final Widget child;
  final bool slideIn;

  @override
  State<NavPop> createState() => _NavPopState();
}

class _NavPopState extends State<NavPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: NavPop.duration,
  );
  static final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.55,
        end: 1.18,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.18,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 55,
    ),
  ]);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed && !_c.isAnimating) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final t = Curves.easeOut.transform(_c.value);
      return Transform.translate(
        offset: Offset(widget.slideIn ? -10 * (1 - t) : 0, -4 * (1 - t)),
        child: Transform.scale(scale: _scale.transform(_c.value), child: child),
      );
    },
  );
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
    // Android back on Trips / Offers / Account goes to Home first; the app
    // only closes from Home. Pages pushed from a tab sit on routes above
    // this one, so they still pop first. On Home this scope allows the pop
    // and the Home's own scope (RiderHomeBackScope) decides: it steps back
    // through the booking flow and lets the app close only when idle.
    return PopScope(
      canPop: tab == RiderTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (widget.showNav && _tab != RiderTab.home) _select(RiderTab.home);
      },
      child: Scaffold(
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
      ),
    );
  }
}
