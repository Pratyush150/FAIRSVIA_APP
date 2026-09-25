import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// Owner (2026-09-25): pulled up on trip, the sheet must read as a complete
/// page — progress, driver, route, safety toolkit, fare, posters — built
/// from the trip's own figures.
void main() {
  TripState state() => TripState(
    phase: TripPhase.onTrip,
    liveEtaSec: 720,
    liveRemainingM: 4100,
    trip: Trip(
      id: 't1',
      status: TripStatus.inProgress,
      tier: 'economy',
      currency: 'INR',
      fareEstimate: 289,
      paymentMode: 'cash',
      distanceM: 8200,
      durationS: 1500,
      promoCode: 'WELCOME50',
      promoDiscount: 50,
      pickup: const TripEndpoint(
        point: GeoPoint(18.52, 73.85),
        address: 'Shivajinagar Bus Stand, Pune',
      ),
      dropoff: const TripEndpoint(
        point: GeoPoint(18.53, 73.87),
        address: 'Pune Railway Station',
      ),
      stops: const [
        TripStop(point: GeoPoint(18.525, 73.86), address: 'FC Road'),
      ],
    ),
    driver: const AssignedDriver(
      name: 'Amit Kumar',
      rating: 4.8,
      plate: 'MH12PM2285',
    ),
    dropoffAddr: 'Pune Railway Station',
    pickupAddr: 'Shivajinagar Bus Stand, Pune',
  );

  Future<void> pump(
    WidgetTester tester, {
    double width = 411,
    double textScale = 1,
  }) async {
    final s = state();
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: s);
    tester.view.physicalSize = Size(width * 3, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: BlocProvider<TripCubit>.value(
              value: cubit,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OnTripSheet(state: s),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('pulled up, on trip shows every below-the-fold section', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('on-trip-extras')), findsOneWidget);
    expect(find.text('Trip progress'), findsOneWidget);
    // Real figures: 4.1 km left of 8.2 km → half way.
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('ride-progress-bar')),
    );
    expect(bar.value, closeTo(0.5, 0.01));
    expect(
      find.text('${Fmt.distance(4100)} of ${Fmt.distance(8200)}'),
      findsOneWidget,
    );
    expect(
      find.textContaining(RegExp(r'^Expected at \d{1,2}:\d\d (AM|PM)$')),
      findsOneWidget,
    );
    expect(find.text('Your driver'), findsOneWidget);
    // The destination stays said once, in the header.
    expect(find.textContaining('Pune Railway Station'), findsOneWidget);
    expect(find.text('Safety'), findsWidgets);
    for (final k in ['sos', 'share', 'contacts', 'help']) {
      expect(find.byKey(ValueKey('toolkit-$k')), findsOneWidget);
    }
    expect(find.text('Trip details'), findsOneWidget);
    expect(find.text('Shivajinagar Bus Stand, Pune'), findsOneWidget);
    expect(find.text('Promo WELCOME50'), findsOneWidget);
    expect(find.text('Cash'), findsWidgets);
    expect(find.byType(PromoCarousel), findsOneWidget);
    expect(find.text('Plan your ride back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at 360dp with 1.5x text', (tester) async {
    await pump(tester, width: 360, textScale: 1.5);
    expect(find.byKey(const ValueKey('on-trip-extras')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
