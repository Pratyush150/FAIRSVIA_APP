import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:core/core.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// Audit items 3.8 (finding a driver), 3.10 (in trip) and 3.11 (ride
/// completed), pumped through the real phase switcher so the pinned footer
/// is part of what is checked.
void main() {
  setUp(() => Market.current = Market.india);
  tearDown(() => Market.current = Market.unitedStates);

  Trip trip({
    TripStatus status = TripStatus.matching,
    String paymentMode = 'cash',
    DateTime? requestedAt,
  }) =>
      Trip(
        id: 't1',
        status: status,
        tier: 'economy',
        currency: 'INR',
        fareEstimate: 101.6,
        paymentMode: paymentMode,
        requestedAt: requestedAt,
        pickup: const TripEndpoint(point: GeoPoint(18.52, 73.85)),
        dropoff: const TripEndpoint(point: GeoPoint(18.53, 73.87)),
      );

  late MockTripCubit cubit;

  Future<void> pump(WidgetTester tester, TripState state) async {
    cubit = MockTripCubit();
    when(() => cubit.reset()).thenReturn(null);
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: BlocProvider<TripCubit>.value(
          value: cubit,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: RideSheetForPhase(
                state: state, onSearch: () {}, onPickSaved: (_) {}),
          ),
        ),
      ),
    ));
    // The radar never settles; step through the phase cross-fade instead.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  group('finding a driver (3.8)', () {
    TripState searching({DateTime? requestedAt}) => TripState(
          phase: TripPhase.searching,
          trip: trip(requestedAt: requestedAt),
          dropoffAddr: 'Pune Railway Station, Agarkar Nagar, Pune',
          estimate: const TripEstimate(
            distanceM: 4000,
            durationS: 900,
            polyline: '',
            surge: 1,
            currency: 'INR',
            pickup: GeoPoint(18.52, 73.85),
            dropoff: GeoPoint(18.53, 73.87),
            tiers: [
              FareTier(
                  tier: 'economy',
                  label: 'Economy',
                  capacity: 4,
                  fare: 101.6,
                  currency: 'INR',
                  etaSeconds: 180),
            ],
          ),
        );

    testWidgets('says what was booked: tier, whole-rupee fare, payment',
        (tester) async {
      await pump(tester, searching());
      expect(find.text('Economy · ₹102 · Cash'), findsOneWidget);
      expect(find.text('To Pune Railway Station'), findsOneWidget);
      expect(find.text('Looking for nearby drivers…'), findsOneWidget);
      expect(find.text('Still looking…'), findsNothing);
    });

    testWidgets('after 45 s it says it is still looking', (tester) async {
      await pump(tester, searching());
      await tester.pump(const Duration(seconds: 44));
      expect(find.text('Still looking…'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Still looking…'), findsOneWidget);
      expect(find.text('Drivers nearby are busy. We’ll keep looking.'),
          findsOneWidget);
    });

    testWidgets('a search restored after 45 s already says so',
        (tester) async {
      await pump(
          tester,
          searching(
              requestedAt:
                  DateTime.now().subtract(const Duration(seconds: 60))));
      expect(find.text('Still looking…'), findsOneWidget);
    });

    test('summary leaves out a fare nothing has priced', () {
      final s = TripState(
        phase: TripPhase.searching,
        trip: const Trip(
          id: 't2',
          status: TripStatus.matching,
          tier: 'economy',
          currency: 'INR',
          pickup: TripEndpoint(point: GeoPoint(18.52, 73.85)),
          dropoff: TripEndpoint(point: GeoPoint(18.53, 73.87)),
        ),
      );
      expect(searchingSummary(s), 'Economy · Card');
    });
  });

  group('in trip (3.10)', () {
    TripState onTrip({int? remainingM}) => TripState(
          phase: TripPhase.onTrip,
          trip: trip(status: TripStatus.inProgress),
          dropoffAddr: 'Phoenix Marketcity, Viman Nagar, Pune',
          liveEtaSec: 600,
          liveRemainingM: remainingM,
        );

    testWidgets('names the destination exactly once', (tester) async {
      await pump(tester, onTrip(remainingM: 5000));
      expect(find.text('On the way to Phoenix Marketcity'), findsOneWidget);
      expect(find.textContaining('Phoenix Marketcity'), findsOneWidget);
    });

    testWidgets('offers "Add a stop" until the last kilometre',
        (tester) async {
      await pump(tester, onTrip(remainingM: 5000));
      expect(find.text('Add a stop'), findsOneWidget);
      await pump(tester, onTrip(remainingM: 800));
      expect(find.text('Add a stop'), findsNothing);
      expect(find.text('Pre-book a ride'), findsOneWidget);
    });

    testWidgets('"Arriving soon" under 500 m, destination still once',
        (tester) async {
      await pump(tester, onTrip(remainingM: 400));
      expect(find.text('Arriving soon'), findsOneWidget);
      expect(find.textContaining('Phoenix Marketcity'), findsOneWidget);
    });
  });

  group('ride completed (3.11)', () {
    const breakdown = FareBreakdown(
      baseFare: 30,
      distanceFare: 30,
      timeFare: 10,
      bookingFee: 5,
    );
    const done = TripState(
      phase: TripPhase.completed,
      fareFinal: 75,
      breakdown: breakdown,
      receipt: Receipt(tripId: 't1', fare: 75, currency: 'INR', tip: 0),
    );

    testWidgets('one "Total" line; the breakdown folds under it',
        (tester) async {
      await pump(tester, done);
      expect(find.text('Total ₹75'), findsOneWidget);
      // The total is not repeated as a sub-headline.
      expect(find.textContaining('₹75'), findsOneWidget);
      expect(find.text('Base fare'), findsNothing);

      await tester.tap(find.text('Total ₹75'));
      await tester.pump();
      expect(find.text('Base fare'), findsOneWidget);
      expect(find.text('Booking fee'), findsOneWidget);

      await tester.tap(find.text('Total ₹75'));
      await tester.pump();
      expect(find.text('Base fare'), findsNothing);
    });

    testWidgets('tips come from the market, plus Custom', (tester) async {
      await pump(tester, done);
      for (final t in Market.current.tipPresets) {
        expect(find.text(Money.format(t, wholeOnly: true)), findsOneWidget);
      }
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('Done is pinned below the scrolling content', (tester) async {
      await pump(tester, done);
      final done_ = find.widgetWithText(PrimaryButton, 'Done');
      expect(done_, findsOneWidget);
      // Not inside the sheet's scroll view: it cannot scroll away.
      expect(
          find.ancestor(of: done_, matching: find.byType(SingleChildScrollView)),
          findsNothing);
      when(() => cubit.finishRide()).thenAnswer((_) async {});
      await tester.tap(done_);
      // Done sends any selected tip, then closes the ride.
      verify(() => cubit.finishRide()).called(1);
    });
  });
}
