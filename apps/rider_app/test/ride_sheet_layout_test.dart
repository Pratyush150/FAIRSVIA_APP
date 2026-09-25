import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/layout/rider_sheet_heights.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// Every live-ride sheet, and every transition between them, must lay out
/// without overflow on a real phone size. A RenderFlex overflow was seen on
/// the emulator (Pixel, 411×914 logical) at the arrived → on-trip switch.
/// Scopes [f] to the pickable tier list: the compare table further down the
/// sheet legitimately repeats tier names and fares.
Finder inTierList(Finder f) =>
    find.descendant(of: find.byKey(const Key('ride-tier-list')), matching: f);

void main() {
  const driver = AssignedDriver(
    name: 'Bekzod',
    rating: 4.9,
    vehicleMake: 'Chevrolet',
    vehicleModel: 'Cobalt',
    vehicleColor: 'White',
    plate: '01A123BC',
    phone: '+998901110002',
    etaSec: 240,
  );
  final trip = TripState(
    trip: Trip(
      id: 't1',
      status: TripStatus.accepted,
      tier: 'economy',
      startOtp: '4827',
      pickup: const TripEndpoint(point: GeoPoint(41.31, 69.24)),
      dropoff: const TripEndpoint(point: GeoPoint(41.33, 69.28)),
      stops: const [
        TripStop(
          point: GeoPoint(41.32, 69.25),
          address: 'Chorsu Bazaar, Shayxontohur district, Tashkent',
        ),
        TripStop(
          point: GeoPoint(41.32, 69.26),
          address: 'Amir Temur Square, Tashkent',
        ),
        TripStop(point: GeoPoint(41.32, 69.27), address: 'Tashkent City Mall'),
      ],
    ),
    driver: driver,
    dropoffAddr: '301 Biscayne Blvd, Miami, FL 33132, USA',
    pickupAddr: '1 E Flagler St, Miami, FL 33132, USA',
  );

  Future<void> run(
    WidgetTester tester,
    List<TripPhase> phases, {
    Size size = const Size(411, 914),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final cubit = MockTripCubit();
    var state = trip.copyWith(phase: phases.first);
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);

    Widget app(TripState s) => MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(top: 24, bottom: 24),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: BlocProvider<TripCubit>.value(
            value: cubit,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: RideSheetForPhase(
                state: s,
                onSearch: () {},
                onPickSaved: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(state));
    await tester.pump();
    for (final phase in phases.skip(1)) {
      state = state.copyWith(phase: phase);
      await tester.pumpWidget(app(state));
      // Step through the whole cross-fade/resize, frame by frame.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }
  }

  const live = [
    TripPhase.driverEnRoute,
    TripPhase.driverArrived,
    TripPhase.onTrip,
  ];

  testWidgets('live sheets and their transitions never overflow', (
    tester,
  ) async {
    await run(tester, live);
    expect(tester.takeException(), isNull);
  });

  testWidgets('…nor at a large accessibility text size', (tester) async {
    await run(tester, live, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('…nor on a small phone', (tester) async {
    await run(tester, live, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking-phase sheets and their transitions never overflow', (
    tester,
  ) async {
    await run(tester, const [
      TripPhase.requesting,
      TripPhase.searching,
      TripPhase.driverEnRoute,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed at 75%: tips and Done fit without scrolling (411×914)',
    (tester) async {
      await run(tester, const [TripPhase.onTrip, TripPhase.completed]);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      final screenH = 914.0;
      final done = find.text('Done');
      expect(done, findsOneWidget);
      final tips = find.text('Custom');
      expect(tips, findsWidgets);
      final tipBottom = tester.getBottomLeft(tips.first).dy;
      final doneTop = tester.getTopLeft(done).dy;
      // Tip chips visible on screen, above the pinned Done — no scroll needed.
      expect(tipBottom, lessThan(doneTop));
      expect(doneTop, lessThan(screenH));
      // Nothing scrolled: the first scrollable in the sheet is at offset 0 and
      // has no extent left to scroll.
      final scrollables = find
          .byType(Scrollable)
          .evaluate()
          .map((e) => (e as StatefulElement).state as ScrollableState);
      for (final sc in scrollables) {
        if (sc.position.axis == Axis.vertical &&
            sc.position.hasContentDimensions) {
          expect(
            sc.position.maxScrollExtent,
            lessThan(1),
            reason: 'completed page content must fit without scrolling',
          );
        }
      }
    },
  );

  testWidgets('the completed sheet (pinned Done) never overflows', (
    tester,
  ) async {
    // Also the on-trip → completed switch, where the footer appears.
    for (final (size, scale) in const [
      (Size(411, 914), 1.0),
      (Size(411, 914), 1.3),
      (Size(360, 640), 1.0),
      (Size(360, 640), 1.3),
    ]) {
      await run(
        tester,
        const [TripPhase.onTrip, TripPhase.completed],
        size: size,
        textScale: scale,
      );
      expect(tester.takeException(), isNull, reason: 'at $size ×$scale');
      // The card has grown to its set share (RiderSheetHeights.completed).
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.getRect(find.byType(RideSheetForPhase)).height,
        closeTo(size.height * RiderSheetHeights.current.completed, 1),
        reason: 'at $size ×$scale',
      );
    }
  });

  testWidgets('a long search ("Still looking…") never overflows', (
    tester,
  ) async {
    await run(
      tester,
      const [TripPhase.searching],
      size: const Size(360, 640),
      textScale: 1.3,
    );
    await tester.pump(const Duration(seconds: 46));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Still looking…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ride options sheet never overflows (with its footer)', (
    tester,
  ) async {
    final estimate = TripEstimate(
      distanceM: 1500,
      durationS: 420,
      polyline: '',
      surge: 1,
      currency: 'USD',
      pickup: const GeoPoint(25.77, -80.19),
      dropoff: const GeoPoint(25.78, -80.18),
      tiers: const [
        FareTier(
          tier: 'economy',
          label: 'Economy',
          capacity: 4,
          fare: 7.33,
          currency: 'USD',
          etaSeconds: 180,
        ),
        FareTier(
          tier: 'comfort',
          label: 'Comfort',
          capacity: 4,
          fare: 9.89,
          currency: 'USD',
          etaSeconds: null,
        ),
        FareTier(
          tier: 'xl',
          label: 'XL',
          capacity: 6,
          fare: 12.63,
          currency: 'USD',
          etaSeconds: null,
        ),
        FareTier(
          tier: 'premium',
          label: 'Premium',
          capacity: 4,
          fare: 15.20,
          currency: 'USD',
          etaSeconds: null,
        ),
      ],
    );
    for (final size in const [Size(411, 914), Size(360, 640)]) {
      tester.view.physicalSize = size * 2.625;
      tester.view.devicePixelRatio = 2.625;
      final cubit = MockTripCubit();
      final state = trip.copyWith(
        phase: TripPhase.choosingRide,
        estimate: estimate,
        selectedTier: 'economy',
      );
      whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.only(top: 24, bottom: 24),
            ),
            child: Scaffold(
              body: BlocProvider<TripCubit>.value(
                value: cubit,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: RideSheetForPhase(
                    state: state,
                    onSearch: () {},
                    onPickSaved: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull, reason: 'at $size');
      // 3.7: each row says when the car comes and when you arrive; the
      // payment choice sits in the footer right above Confirm.
      expect(find.textContaining('Pickup in 3 min · Drop '), findsOneWidget);
      expect(find.text('Cash'), findsWidgets);
    }
    tester.view.reset();
  });

  /// Pune pilot: six ride types, bike and auto first (cheapest first), in
  /// rupees. The list must still lay out on a small phone and at large text,
  /// keep Confirm reachable, and show every row once scrolled to.
  testWidgets('six ride types (bike, auto + four cars) never overflow', (
    tester,
  ) async {
    final estimate = TripEstimate(
      distanceM: 5200,
      durationS: 900,
      polyline: '',
      surge: 1,
      currency: 'INR',
      pickup: const GeoPoint(18.53, 73.8475),
      dropoff: const GeoPoint(18.56, 73.81),
      tiers: const [
        FareTier(
          tier: 'bike',
          label: 'Bike',
          capacity: 1,
          fare: 53,
          currency: 'INR',
          etaSeconds: 120,
        ),
        FareTier(
          tier: 'auto',
          label: 'Auto',
          capacity: 3,
          fare: 104,
          currency: 'INR',
          etaSeconds: 180,
        ),
        FareTier(
          tier: 'economy',
          label: 'Economy',
          capacity: 4,
          fare: 127,
          currency: 'INR',
          etaSeconds: 240,
        ),
        FareTier(
          tier: 'comfort',
          label: 'Comfort',
          capacity: 4,
          fare: 162,
          currency: 'INR',
          etaSeconds: null,
        ),
        FareTier(
          tier: 'xl',
          label: 'XL',
          capacity: 6,
          fare: 234,
          currency: 'INR',
          etaSeconds: 420,
        ),
        FareTier(
          tier: 'premium',
          label: 'Premium',
          capacity: 4,
          fare: 335,
          currency: 'INR',
          etaSeconds: null,
        ),
      ],
    );
    for (final (size, scale) in const [
      (Size(411, 914), 1.0),
      (Size(360, 640), 1.0),
      (Size(360, 640), 1.3),
    ]) {
      tester.view.physicalSize = size * 2.625;
      tester.view.devicePixelRatio = 2.625;
      final cubit = MockTripCubit();
      final state = trip.copyWith(
        phase: TripPhase.choosingRide,
        estimate: estimate,
        selectedTier: FareTier.defaultTier(estimate.tiers),
      );
      // The one-seat bike leads the list but is not what gets pre-picked.
      expect(state.selectedTier, 'auto');
      whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              padding: const EdgeInsets.only(top: 24, bottom: 24),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: BlocProvider<TripCubit>.value(
                value: cubit,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: RideSheetForPhase(
                    state: state,
                    onSearch: () {},
                    onPickSaved: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final at = 'at $size x$scale';
      expect(tester.takeException(), isNull, reason: at);
      // Cheapest first: the bike row sits above the auto row, above economy.
      expect(inTierList(find.text('Bike')), findsOneWidget, reason: at);
      expect(inTierList(find.text('Auto')), findsOneWidget, reason: at);
      expect(
        tester.getTopLeft(inTierList(find.text('Bike'))).dy,
        lessThan(tester.getTopLeft(inTierList(find.text('Auto'))).dy),
        reason: at,
      );
      expect(inTierList(find.text('₹53')), findsOneWidget, reason: at);
      // The footer (payment choice above Confirm) stays on screen.
      expect(find.text('Cash'), findsWidgets, reason: at);
      // Seats: 1 on the bike, 3 in the auto.
      final bikeRow = find
          .ancestor(
            of: inTierList(find.text('Bike')),
            matching: find.byType(InkWell),
          )
          .first;
      expect(
        find.descendant(of: bikeRow, matching: find.text('1')),
        findsOneWidget,
        reason: at,
      );
      final autoRow = find
          .ancestor(
            of: inTierList(find.text('Auto')),
            matching: find.byType(InkWell),
          )
          .first;
      expect(
        find.descendant(of: autoRow, matching: find.text('3')),
        findsOneWidget,
        reason: at,
      );
      // Comfort has no car nearby; the premium row is further down the list.
      await tester.scrollUntilVisible(
        inTierList(find.text('Premium')),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(inTierList(find.text('Premium')), findsOneWidget, reason: at);
      expect(tester.takeException(), isNull, reason: at);
    }
    tester.view.reset();
  });

  testWidgets('an auto or bike with none nearby says so in its own words', (
    tester,
  ) async {
    final estimate = TripEstimate(
      distanceM: 2000,
      durationS: 400,
      polyline: '',
      surge: 1,
      currency: 'INR',
      pickup: const GeoPoint(18.53, 73.8475),
      dropoff: const GeoPoint(18.54, 73.84),
      tiers: const [
        FareTier(
          tier: 'bike',
          label: 'Bike',
          capacity: 1,
          fare: 21,
          currency: 'INR',
          etaSeconds: null,
        ),
        FareTier(
          tier: 'auto',
          label: 'Auto',
          capacity: 3,
          fare: 40,
          currency: 'INR',
          etaSeconds: null,
        ),
        FareTier(
          tier: 'economy',
          label: 'Economy',
          capacity: 4,
          fare: 81,
          currency: 'INR',
          etaSeconds: 200,
        ),
      ],
    );
    tester.view.physicalSize = const Size(411, 914) * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final cubit = MockTripCubit();
    final state = trip.copyWith(
      phase: TripPhase.choosingRide,
      estimate: estimate,
      selectedTier: 'economy',
    );
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BlocProvider<TripCubit>.value(
            value: cubit,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: RideSheetForPhase(
                state: state,
                onSearch: () {},
                onPickSaved: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      find.text('No bikes nearby now — we\'ll keep looking'),
      findsOneWidget,
    );
    expect(
      find.text('No autos nearby now — we\'ll keep looking'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
