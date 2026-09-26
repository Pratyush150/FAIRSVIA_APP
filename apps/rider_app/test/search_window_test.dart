import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/trip/ride_status.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// The owner's rule: every ride type is bright and bookable (one with no car
/// nearby says so and the search keeps looking for a while); the finding
/// sheet shows how long it can still look; a search that runs out offers
/// "Try again" and "Schedule for later".
void main() {
  const estimate = TripEstimate(
    distanceM: 6000,
    durationS: 720,
    polyline: '',
    surge: 1,
    currency: 'INR',
    pickup: GeoPoint(18.53, 73.8475),
    dropoff: GeoPoint(18.54, 73.87),
    tiers: [
      FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 89,
        currency: 'INR',
        etaSeconds: 240,
      ),
      FareTier(
        tier: 'comfort',
        label: 'Comfort',
        capacity: 4,
        fare: 100,
        currency: 'INR',
        etaSeconds: null,
      ), // no comfort car nearby
    ],
  );

  late MockTripCubit cubit;

  Future<void> pumpSheet(WidgetTester tester, TripState state) async {
    tester.view.physicalSize = const Size(411, 914) * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    cubit = MockTripCubit();
    when(() => cubit.confirmRide()).thenAnswer((_) async {});
    when(() => cubit.selectTier(any())).thenAnswer((_) async {});
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BlocProvider<TripCubit>.value(
            value: cubit,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
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
  }

  TripState choosing({String tier = 'economy', String? error}) => TripState(
    phase: TripPhase.choosingRide,
    estimate: estimate,
    selectedTier: tier,
    dropoffAddr: 'Pune Railway Station',
    error: error,
  );

  group('choose ride: every tier bright and bookable', () {
    testWidgets(
      'a tier with no car nearby is not dimmed and says we keep looking',
      (tester) async {
        await pumpSheet(tester, choosing());
        final note = find.text('No cars nearby now — we\'ll keep looking');
        expect(note, findsOneWidget);
        final dimmed = find.ancestor(
          of: note,
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity < 1,
          ),
        );
        expect(dimmed, findsNothing);
        expect(find.text('No cars nearby right now'), findsNothing);
      },
    );

    testWidgets('tapping the unavailable tier selects it', (tester) async {
      await pumpSheet(tester, choosing());
      await tester.tap(find.text('Comfort').first);
      verify(() => cubit.selectTier('comfort')).called(1);
    });

    testWidgets('Confirm is enabled for an unavailable tier', (tester) async {
      await pumpSheet(tester, choosing(tier: 'comfort'));
      final label = find.text('Confirm Comfort · ₹100');
      expect(label, findsOneWidget);
      final button = tester.widget<PrimaryButton>(
        find.ancestor(of: label, matching: find.byType(PrimaryButton)),
      );
      expect(button.onPressed, isNotNull);
      await tester.tap(label);
      verify(() => cubit.confirmRide()).called(1);
    });

    testWidgets('after the search runs out: Try again and Schedule for later', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        choosing(tier: 'comfort', error: TripCubit.noDriversNearby),
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Schedule for later'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      verify(() => cubit.confirmRide()).called(1);
    });
  });

  group('finding a driver: the search is bounded', () {
    test('time-left wording', () {
      expect(
        RideStatus.searchTimeLeft(const Duration(seconds: 180)),
        'Still looking… up to 3 min',
      );
      expect(
        RideStatus.searchTimeLeft(const Duration(seconds: 61)),
        'Still looking… up to 2 min',
      );
      expect(
        RideStatus.searchTimeLeft(const Duration(seconds: 42)),
        'Still looking… up to 42 s',
      );
      expect(RideStatus.searchTimeLeft(Duration.zero), 'Finishing the search…');
    });

    testWidgets('shows the time left and a progress ring', (tester) async {
      await pumpSheet(
        tester,
        TripState(
          phase: TripPhase.searching,
          estimate: estimate,
          selectedTier: 'comfort',
          dropoffAddr: 'Pune Railway Station',
          searchEndsAt: DateTime.now().add(const Duration(seconds: 179)),
        ),
      );
      expect(find.text('Still looking… up to 3 min'), findsOneWidget);
      expect(find.bySemanticsLabel('Search time left'), findsOneWidget);
    });
  });
}
