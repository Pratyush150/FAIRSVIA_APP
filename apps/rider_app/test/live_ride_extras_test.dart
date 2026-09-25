import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// The pulled-up (expanded) part of the finding-driver and driver-arriving
/// sheets: real trip data only, every section present, no overflow at
/// 360 dp with 1.5x text.
void main() {
  const driver = AssignedDriver(
    name: 'Ava',
    rating: 4.9,
    vehicleMake: 'Toyota',
    vehicleModel: 'Prius',
    vehicleColor: 'White',
    plate: 'ABC123',
    phone: '+1 305-555-0123',
    etaSec: 240,
  );
  final trip = Trip(
    id: 't1',
    status: TripStatus.accepted,
    tier: 'economy',
    startOtp: '4827',
    paymentMode: 'cash',
    pickup: const TripEndpoint(
        point: GeoPoint(18.52, 73.85), address: 'Central Square, Gate 2'),
    dropoff: const TripEndpoint(
        point: GeoPoint(18.53, 73.87), address: 'Railway Station, North Exit'),
  );

  Future<void> pump(WidgetTester tester, Widget child, TripState state) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(360, 3000), textScaler: TextScaler.linear(1.5)),
        child: Scaffold(
          body: BlocProvider<TripCubit>.value(
            value: cubit,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('searching extras: booked ride, route, payment, safety, tips',
      (tester) async {
    final state = TripState(
        phase: TripPhase.searching, trip: trip, paymentMode: 'cash');
    await pump(tester, LiveRideExtras(state: state, searching: true), state);
    expect(tester.takeException(), isNull);
    expect(find.text('What you booked'), findsOneWidget);
    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Central Square, Gate 2'), findsOneWidget);
    expect(find.text('Railway Station, North Exit'), findsOneWidget);
    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('Stay safe'), findsOneWidget);
    expect(find.text('Share trip'), findsOneWidget);
    expect(find.text('While you wait'), findsOneWidget);
    expect(find.textContaining('Cancelling now is free'), findsOneWidget);
    // No driver yet: no pickup ETA invented.
    expect(find.text('Driver arriving'), findsNothing);
  });

  testWidgets('driver sheet extras: ETA with clock time, toolkit, tips',
      (tester) async {
    final state = TripState(
        phase: TripPhase.driverEnRoute, trip: trip, driver: driver);
    await pump(
        tester, DriverInfoSheet(state: state, arrived: false), state);
    expect(tester.takeException(), isNull);
    expect(find.text('Driver arriving'), findsOneWidget);
    expect(find.text('4 min away'), findsOneWidget);
    expect(find.textContaining(RegExp(r'At your pickup by \d{1,2}:\d\d (AM|PM)')),
        findsOneWidget);
    expect(find.text('Going to'), findsOneWidget);
    expect(find.text('SOS & contacts'), findsOneWidget);
    expect(find.text('Meeting your driver'), findsOneWidget);
    expect(find.textContaining('may carry a fee'), findsOneWidget);
  });
}
