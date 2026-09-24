import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// Every live-ride sheet, and every transition between them, must lay out
/// without overflow on a real phone size. A RenderFlex overflow was seen on
/// the emulator (Pixel, 411×914 logical) at the arrived → on-trip switch.
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
        TripStop(point: GeoPoint(41.32, 69.25), address: 'Chorsu Bazaar, Shayxontohur district, Tashkent'),
        TripStop(point: GeoPoint(41.32, 69.26), address: 'Amir Temur Square, Tashkent'),
        TripStop(point: GeoPoint(41.32, 69.27), address: 'Tashkent City Mall'),
      ],
    ),
    driver: driver,
    dropoffAddr: '301 Biscayne Blvd, Miami, FL 33132, USA',
    pickupAddr: '1 E Flagler St, Miami, FL 33132, USA',
  );

  Future<void> run(WidgetTester tester, List<TripPhase> phases,
      {Size size = const Size(411, 914), double textScale = 1.0}) async {
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

  testWidgets('live sheets and their transitions never overflow', (tester) async {
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

  testWidgets('booking-phase sheets and their transitions never overflow', (tester) async {
    await run(tester, const [
      TripPhase.requesting,
      TripPhase.searching,
      TripPhase.driverEnRoute,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the completed sheet (pinned Done) never overflows', (tester) async {
    // Also the on-trip → completed switch, where the footer appears.
    for (final (size, scale) in const [
      (Size(411, 914), 1.0),
      (Size(360, 640), 1.0),
      (Size(360, 640), 1.3),
    ]) {
      await run(tester, const [TripPhase.onTrip, TripPhase.completed],
          size: size, textScale: scale);
      expect(tester.takeException(), isNull, reason: 'at $size ×$scale');
    }
  });

  testWidgets('a long search ("Still looking…") never overflows', (tester) async {
    await run(tester, const [TripPhase.searching],
        size: const Size(360, 640), textScale: 1.3);
    await tester.pump(const Duration(seconds: 46));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Still looking…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ride options sheet never overflows (with its footer)', (tester) async {
    final estimate = TripEstimate(
      distanceM: 1500,
      durationS: 420,
      polyline: '',
      surge: 1,
      currency: 'USD',
      pickup: const GeoPoint(25.77, -80.19),
      dropoff: const GeoPoint(25.78, -80.18),
      tiers: const [
        FareTier(tier: 'economy', label: 'Economy', capacity: 4, fare: 7.33, currency: 'USD', etaSeconds: 180),
        FareTier(tier: 'comfort', label: 'Comfort', capacity: 4, fare: 9.89, currency: 'USD', etaSeconds: null),
        FareTier(tier: 'xl', label: 'XL', capacity: 6, fare: 12.63, currency: 'USD', etaSeconds: null),
        FareTier(tier: 'premium', label: 'Premium', capacity: 4, fare: 15.20, currency: 'USD', etaSeconds: null),
      ],
    );
    for (final size in const [Size(411, 914), Size(360, 640)]) {
      tester.view.physicalSize = size * 2.625;
      tester.view.devicePixelRatio = 2.625;
      final cubit = MockTripCubit();
      final state = trip.copyWith(
          phase: TripPhase.choosingRide, estimate: estimate, selectedTier: 'economy');
      whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(size: size, padding: const EdgeInsets.only(top: 24, bottom: 24)),
          child: Scaffold(
            body: BlocProvider<TripCubit>.value(
              value: cubit,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: RideSheetForPhase(state: state, onSearch: () {}, onPickSaved: (_) {}),
              ),
            ),
          ),
        ),
      ));
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
}
