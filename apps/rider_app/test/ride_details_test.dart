import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// The rider's "Details" control on a ride that is actually happening: what it
/// costs and which car is coming. Both were previously unreachable between
/// confirming a ride and arriving at the destination.
void main() {
  const pickup = GeoPoint(18.5074, 73.8077);
  const dropoff = GeoPoint(18.5314, 73.8446);

  const driver = AssignedDriver(
    id: 'd1',
    name: 'Ava',
    rating: 4.9,
    vehicleMake: 'Toyota',
    vehicleModel: 'Camry',
    vehicleColor: 'White',
    plate: 'MH12AB3456',
    phone: '+1 305-555-0123',
  );

  final trip = Trip(
    id: 't1',
    status: TripStatus.inProgress,
    tier: 'economy',
    pickup: const TripEndpoint(point: pickup, address: 'Paud Road'),
    dropoff: const TripEndpoint(point: dropoff, address: 'Shivajinagar'),
    distanceM: 6201,
    durationS: 1094,
    fareEstimate: 13.68,
    paymentMode: 'cash',
  );

  Future<void> pump(WidgetTester tester, Widget child, TripState state) async {
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<TripCubit>.value(
            value: cubit,
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('fare', () {
    testWidgets('shows the booked fare while the ride is still running', (
      tester,
    ) async {
      final state = TripState(phase: TripPhase.onTrip, trip: trip);
      await pump(tester, RideDetailsContent(state: state), state);

      expect(find.text('Estimated fare'), findsOneWidget);
      expect(find.text('\$13.68'), findsOneWidget);
    });

    testWidgets('shows the settled total once the ride is priced', (
      tester,
    ) async {
      final state = TripState(
        phase: TripPhase.completed,
        trip: trip,
        fareFinal: 11.99,
      );
      await pump(tester, RideDetailsContent(state: state), state);

      expect(find.text('Total fare'), findsOneWidget);
      expect(find.text('\$11.99'), findsOneWidget);
    });

    testWidgets('says the fare is unknown rather than showing zero', (
      tester,
    ) async {
      const state = TripState(phase: TripPhase.onTrip);
      await pump(tester, const RideDetailsContent(state: state), state);

      expect(find.text(RideDetailsContent.unknownFare), findsOneWidget);
      expect(find.text('\$0.00'), findsNothing);
      expect(find.text('\$0'), findsNothing);
    });

    testWidgets('a zero receipt does not beat the fare we actually settled', (
      tester,
    ) async {
      final state = TripState(
        phase: TripPhase.completed,
        trip: trip,
        fareFinal: 11.99,
        receipt: const Receipt(tripId: 't1', fare: 0, currency: 'USD'),
      );
      await pump(tester, RideDetailsContent(state: state), state);

      expect(find.text('\$11.99'), findsOneWidget);
      expect(find.text('\$0.00'), findsNothing);
    });
  });

  group('vehicle', () {
    testWidgets('names the driver, the car and the plate', (tester) async {
      final state = TripState(
        phase: TripPhase.onTrip,
        trip: trip,
        driver: driver,
      );
      await pump(tester, RideDetailsContent(state: state), state);

      expect(find.text('Ava'), findsOneWidget);
      expect(find.text('4.9'), findsOneWidget);
      expect(find.text('White Toyota Camry'), findsOneWidget);
      expect(find.text('MH12AB3456'), findsOneWidget);
    });

    testWidgets('builds the vehicle line from whatever the payload carried', (
      tester,
    ) async {
      expect(RideDetailsContent.vehicleLine(driver), 'White Toyota Camry');
      expect(
        RideDetailsContent.vehicleLine(
          const AssignedDriver(name: 'B', rating: 5, vehicleModel: 'Swift'),
        ),
        'Swift',
      );
      // Nothing to say beats saying "  ".
      expect(
        RideDetailsContent.vehicleLine(
          const AssignedDriver(name: 'B', rating: 5),
        ),
        isNull,
      );
      expect(RideDetailsContent.vehicleLine(null), isNull);
    });

    testWidgets('omits the car card entirely before a driver is assigned', (
      tester,
    ) async {
      final state = TripState(phase: TripPhase.searching, trip: trip);
      await pump(tester, RideDetailsContent(state: state), state);

      expect(find.text('Vehicle'), findsNothing);
      expect(find.text('Plate'), findsNothing);
    });
  });

  group('route and payment', () {
    testWidgets('shows both addresses, the distance and how it is paid', (
      tester,
    ) async {
      final state = TripState(
        phase: TripPhase.onTrip,
        trip: trip,
        driver: driver,
      );
      await pump(tester, RideDetailsContent(state: state), state);

      expect(find.text('Paud Road'), findsOneWidget);
      expect(find.text('Shivajinagar'), findsOneWidget);
      expect(find.text('Cash to your driver'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
    });
  });

  testWidgets('the Details button opens the sheet', (tester) async {
    final state = TripState(
      phase: TripPhase.onTrip,
      trip: trip,
      driver: driver,
    );
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<TripCubit>.value(
          value: cubit,
          child: Scaffold(body: RideDetailsButton(state: state)),
        ),
      ),
    );
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    expect(find.text('Ride details'), findsOneWidget);
    expect(find.text('\$13.68'), findsOneWidget);
    expect(find.text('White Toyota Camry'), findsOneWidget);
  });
}
