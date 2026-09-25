import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/home/home_cards.dart';
import 'package:rider_app/features/home/home_data.dart';
import 'package:rider_app/features/home/idle_home.dart';
import 'package:rider_app/features/home/rider_bottom_nav.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

Trip _trip(
  String id,
  String? addr,
  GeoPoint p, {
  TripStatus status = TripStatus.completed,
}) => Trip(
  id: id,
  status: status,
  tier: 'economy',
  pickup: const TripEndpoint(point: GeoPoint(18.5, 73.8)),
  dropoff: TripEndpoint(point: p, address: addr),
);

void main() {
  final history = [
    _trip(
      '1',
      'Phoenix Marketcity, Viman Nagar, Pune',
      const GeoPoint(18.56, 73.91),
    ),
    _trip(
      '2',
      'phoenix  marketcity, viman nagar, pune',
      const GeoPoint(18.57, 73.92),
    ),
    _trip(
      '3',
      'Cancelled Place, Pune',
      const GeoPoint(18.4, 73.7),
      status: TripStatus.cancelled,
    ),
    _trip('4', 'Pune Airport, Lohegaon', const GeoPoint(18.58, 73.92)),
    _trip('5', 'Same spot, other text', const GeoPoint(18.58, 73.9201)),
    _trip('6', 'Shaniwar Wada, Pune', const GeoPoint(18.52, 73.85)),
    _trip('7', 'FC Road, Pune', const GeoPoint(18.53, 73.84)),
  ];

  group('home data', () {
    test('recent destinations: completed only, deduped, newest 3', () {
      final r = recentDestinations(history);
      expect(r.map((e) => e.name), [
        'Phoenix Marketcity',
        'Pune Airport',
        'Shaniwar Wada',
      ]);
    });

    test('no history → no recents, no rate card candidate', () {
      expect(recentDestinations(const []), isEmpty);
      expect(lastCompletedRide(const []), isNull);
      expect(lastCompletedRide(history)!.id, '1');
    });

    test('saved place match by distance or address', () {
      const saved = [
        SavedPlace(
          id: 's',
          label: 'Home',
          point: GeoPoint(18.5, 73.8),
          address: 'A',
        ),
      ];
      expect(
        savedPlaceAt(saved, const GeoPoint(18.5001, 73.8001), null),
        isNotNull,
      );
      expect(savedPlaceAt(saved, const GeoPoint(19, 74), 'a'), isNotNull);
      expect(savedPlaceAt(saved, const GeoPoint(19, 74), 'B'), isNull);
    });
  });

  Widget home({
    List<RecentDestination> recents = const [],
    Trip? unrated,
    ValueChanged<RecentDestination>? onPick,
    VoidCallback? onHeart,
    bool isSaved = false,
    VoidCallback? onSearch,
  }) => IdleHome(
    onMenu: () {},
    onRecenter: () {},
    addressLabel: 'Mote Mangal Karyalay Rd, Dattwadi, Pune',
    isSaved: isSaved,
    onToggleSaved: onHeart ?? () {},
    searchBar: HomeSearchBar(onTap: onSearch ?? () {}, onSchedule: () {}),
    sections: [
      if (recents.isNotEmpty)
        HomeSection(
          child: RecentDestinationsCard(
            items: recents,
            onPick: onPick ?? (_) {},
          ),
        ),
      ServicesRow(
        items: [
          ServiceItem('Ride', HomeArt.ride, () {}),
          ServiceItem('Pre-book', HomeArt.prebook, () {}),
          ServiceItem('For others', HomeArt.someoneElse, () {}),
          ServiceItem('Saved places', HomeArt.saved, () {}),
        ],
      ),
      if (unrated != null)
        HomeSection(
          child: RateLastRideCard(trip: unrated, onTap: () {}),
        ),
      const PromoBannerList(kMockPromos),
      const BrandFooter(),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(411, 914),
    double textScale = 1.0,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 24, bottom: 24),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Colors.grey)),
                  Positioned.fill(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('sections render', (tester) async {
    await pump(
      tester,
      home(recents: recentDestinations(history), unrated: history.first),
    );
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Phoenix Marketcity'), findsOneWidget);
    expect(find.text('Pune Airport'), findsOneWidget);
    for (final s in ['Ride', 'Pre-book', 'For others', 'Saved places']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    expect(
      find.text('Mote Mangal Karyalay Rd, Dattwadi, Pune'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Rate your last ride'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Rate your last ride'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(BrandFooter),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(PromoBanner), findsNWidgets(kMockPromos.length));
  });

  testWidgets('recent destinations hidden when there is no history', (
    tester,
  ) async {
    await pump(tester, home());
    expect(find.byType(RecentDestinationsCard), findsNothing);
    expect(find.byIcon(PhosphorIconsRegular.clock), findsNothing);
    // And the card itself renders nothing for an empty list.
    await pump(tester, RecentDestinationsCard(items: const [], onPick: (_) {}));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('tap a recent destination → books to that drop-off', (
    tester,
  ) async {
    RecentDestination? picked;
    final recents = recentDestinations(history);
    await pump(tester, home(recents: recents, onPick: (r) => picked = r));
    await tester.tap(find.text('Pune Airport'));
    expect(picked?.address, 'Pune Airport, Lohegaon');
    expect(picked?.point, const GeoPoint(18.58, 73.92));
  });

  testWidgets('heart saves the current place; saved shows filled', (
    tester,
  ) async {
    var taps = 0;
    await pump(tester, home(onHeart: () => taps++));
    expect(find.byIcon(PhosphorIconsRegular.heart), findsOneWidget);
    await tester.tap(find.byTooltip('Save this place'));
    expect(taps, 1);
    await pump(tester, home(isSaved: true));
    expect(find.byIcon(PhosphorIconsFill.heart), findsOneWidget);
  });

  testWidgets('search bar opens search and pins to the top on scroll', (
    tester,
  ) async {
    var searched = 0;
    await pump(
      tester,
      home(recents: recentDestinations(history), onSearch: () => searched++),
    );
    await tester.tap(find.text('Where to?'));
    expect(searched, 1);
    final before = tester.getTopLeft(find.byType(HomeSearchBar)).dy;
    await tester.drag(find.text('Ride'), const Offset(0, -900));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.byType(HomeSearchBar)).dy;
    expect(after, lessThan(before));
    // Pinned just under the status bar (24) + the sheet's top padding (16).
    expect(after, closeTo(24 + AppSpacing.lg, 1));
  });

  testWidgets('bottom nav switches tabs and hides once a ride starts', (
    tester,
  ) async {
    Widget frame(bool showNav) => RiderTabScaffold(
      showNav: showNav,
      home: const Text('HOME'),
      pages: {
        RiderTab.trips: (_) => const Text('TRIPS'),
        RiderTab.offers: (_) => const Text('OFFERS'),
        RiderTab.account: (_) => const Text('ACCOUNT'),
      },
    );
    await pump(tester, frame(true));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('TRIPS'), findsNothing); // built lazily
    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();
    expect(find.text('TRIPS'), findsOneWidget);
    await tester.tap(find.text('Offers'));
    await tester.pumpAndSettle();
    expect(find.text('OFFERS'), findsOneWidget);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('ACCOUNT'), findsOneWidget);
    // Booking starts: no tabs, straight back to the Home.
    await pump(tester, frame(false));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('ACCOUNT'), findsNothing);
  });

  testWidgets('offers page lists promos', (tester) async {
    await pump(tester, const OffersPage(promos: kMockPromos));
    expect(find.byType(PromoBanner), findsWidgets);
  });

  for (final size in const [Size(360, 640), Size(411, 914)]) {
    for (final dark in [false, true]) {
      testWidgets('no overflow at ${size.width.toInt()}×${size.height.toInt()} '
          '${dark ? 'dark' : 'light'}, text 1.3', (tester) async {
        await pump(
          tester,
          RiderTabScaffold(
            showNav: true,
            home: home(
              recents: recentDestinations(history),
              unrated: history.first,
            ),
            pages: const {},
          ),
          size: size,
          textScale: 1.3,
          theme: dark ? AppTheme.dark : AppTheme.light,
        );
        expect(tester.takeException(), isNull);
        // Scroll the whole sheet through: every section lays out cleanly.
        for (var i = 0; i < 6; i++) {
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -300),
            warnIfMissed: false,
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
