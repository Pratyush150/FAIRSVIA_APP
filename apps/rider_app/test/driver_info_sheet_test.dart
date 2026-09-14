import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

void main() {
  const driverWithPhone = AssignedDriver(
    name: 'Ava',
    rating: 4.9,
    vehicleMake: 'Toyota',
    vehicleModel: 'Prius',
    plate: 'ABC123',
    phone: '+1 305-555-0123',
    etaSec: 240,
  );

  Future<void> pump(
    WidgetTester tester,
    TripState state, {
    bool arrived = false,
    Future<bool> Function(String phone)? dialer,
  }) async {
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<TripCubit>.value(
            value: cubit,
            child: SingleChildScrollView(
              child: DriverInfoSheet(
                state: state,
                arrived: arrived,
                dialer: dialer ?? (_) async => true,
              ),
            ),
          ),
        ),
      ),
    );
    // A plain pump: the stale-location line carries an indeterminate spinner
    // that never "settles".
    await tester.pump();
  }

  testWidgets('Call button dials the driver when the payload has a phone', (
    tester,
  ) async {
    final dialled = <String>[];
    await pump(
      tester,
      const TripState(phase: TripPhase.driverEnRoute, driver: driverWithPhone),
      dialer: (phone) async {
        dialled.add(phone);
        return true;
      },
    );
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    expect(dialled, ['+1 305-555-0123']);
  });

  testWidgets('Call button is hidden when no phone is known', (tester) async {
    await pump(
      tester,
      const TripState(
        phase: TripPhase.driverEnRoute,
        driver: AssignedDriver(name: 'Ava', rating: 4.9),
      ),
    );
    expect(find.text('Call'), findsNothing);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('a dialler failure is surfaced, not swallowed', (tester) async {
    await pump(
      tester,
      const TripState(phase: TripPhase.driverEnRoute, driver: driverWithPhone),
      dialer: (_) async => false,
    );
    await tester.tap(find.text('Call'));
    await tester.pump();
    expect(find.textContaining("Couldn't open the dialler"), findsOneWidget);
  });

  testWidgets('stale driver pings show the waiting line under the ETA', (
    tester,
  ) async {
    await pump(
      tester,
      const TripState(
        phase: TripPhase.driverEnRoute,
        driver: driverWithPhone,
        liveEtaSec: 120,
        driverStale: true,
      ),
    );
    expect(find.text('Arriving in 2 min'), findsOneWidget);
    expect(find.text(DriverInfoSheet.waitingForLocation), findsOneWidget);
  });

  testWidgets('fresh pings hide the waiting line', (tester) async {
    await pump(
      tester,
      const TripState(
        phase: TripPhase.driverEnRoute,
        driver: driverWithPhone,
        liveEtaSec: 120,
      ),
    );
    expect(find.text(DriverInfoSheet.waitingForLocation), findsNothing);
  });

  testWidgets(
    'a failed cancel keeps the sheet, shows the error and Cancel stays tappable',
    (tester) async {
      await pump(
        tester,
        const TripState(
          phase: TripPhase.driverEnRoute,
          driver: driverWithPhone,
          error: TripCubit.cancelFailedMessage,
        ),
      );
      expect(find.text(TripCubit.cancelFailedMessage), findsOneWidget);
      // The ride is still live: the ETA headline is intact, not an error screen.
      expect(find.text('Arriving in 4 min'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this ride?'), findsOneWidget);
    },
  );

  testWidgets('a locked start code is shown on the arrived sheet', (
    tester,
  ) async {
    await pump(
      tester,
      const TripState(
        phase: TripPhase.driverArrived,
        driver: driverWithPhone,
        error: TripCubit.otpLockedMessage,
      ),
      arrived: true,
    );
    expect(find.text('Your driver is here'), findsOneWidget);
    expect(find.text(TripCubit.otpLockedMessage), findsOneWidget);
  });
}
