import 'package:design_system/design_system.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
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

  testWidgets('Call opens the dialler on tel:<driver number>', (tester) async {
    final launched = <Uri>[];
    await pump(
      tester,
      const TripState(phase: TripPhase.driverEnRoute, driver: driverWithPhone),
      dialer: (p) => dialPhone(p, launch: (uri) async {
        launched.add(uri);
        return true;
      }),
    );
    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();
    expect(launched.map((u) => u.toString()), ['tel:+13055550123']);
  });

  testWidgets('••• Share trip status opens the share sheet with the trip', (
    tester,
  ) async {
    final original = tripTextSharer;
    addTearDown(() => tripTextSharer = original);
    final shared = <String>[];
    tripTextSharer = (text, _) async => shared.add(text);

    await pump(
      tester,
      const TripState(
        phase: TripPhase.driverEnRoute,
        driver: driverWithPhone,
        dropoffAddr: 'Chorsu Bazaar',
      ),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share trip status'));
    await tester.pumpAndSettle();

    expect(shared, [
      "I'm on a ${AppBrand.name} ride to Chorsu Bazaar. Car: Toyota Prius, "
          'plate ABC123. Driver: Ava.',
    ]);
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
  });

  testWidgets('cancel lives in the ••• menu, with share, safety and help', (
    tester,
  ) async {
    await pump(
      tester,
      const TripState(phase: TripPhase.driverEnRoute, driver: driverWithPhone),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Share trip status'), findsOneWidget);
    expect(find.text('Safety'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
    await tester.tap(find.text('Cancel ride'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this ride?'), findsOneWidget);
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
    expect(find.textContaining('arriving now'), findsOneWidget);
    expect(find.text(DriverInfoSheet.waitingForLocation), findsOneWidget);
  });

  testWidgets('no waiting line once the driver has arrived and parked', (
    tester,
  ) async {
    await pump(
      tester,
      const TripState(
        phase: TripPhase.driverArrived,
        driver: driverWithPhone,
        driverStale: true,
      ),
      arrived: true,
    );
    await tester.pumpAndSettle();
    expect(find.text(DriverInfoSheet.waitingForLocation), findsNothing);
  });

  testWidgets('an unnamed driver gets an icon, not "YD" initials', (tester) async {
    await pump(
      tester,
      const TripState(
        phase: TripPhase.driverEnRoute,
        driver: AssignedDriver(name: 'Your driver', rating: 5),
      ),
    );
    expect(find.text('YD'), findsNothing);
    expect(find.byIcon(PhosphorIconsRegular.user), findsOneWidget);
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
      expect(find.textContaining('arriving in 4 min'), findsOneWidget);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel ride'));
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
    expect(find.text('Ava has arrived'), findsOneWidget);
    expect(find.text(TripCubit.otpLockedMessage), findsOneWidget);
  });

  testWidgets('shows the ride PIN, pickup, ride type and payment', (tester) async {
    await pump(
      tester,
      TripState(
        phase: TripPhase.driverArrived,
        driver: driverWithPhone,
        pickupAddr: '1 Amir Temur Ave, Tashkent',
        paymentMode: 'cash',
        trip: Trip(
          id: 't1',
          status: TripStatus.arrived,
          tier: 'comfort',
          startOtp: '4827',
          paymentMode: 'cash',
          pickup: const TripEndpoint(
              point: GeoPoint(41.31, 69.24), address: '1 Amir Temur Ave, Tashkent'),
          dropoff: const TripEndpoint(point: GeoPoint(41.33, 69.28)),
        ),
      ),
      arrived: true,
    );
    expect(find.text('Ride PIN'), findsOneWidget);
    for (final d in ['4', '8', '2', '7']) {
      expect(find.text(d), findsOneWidget);
    }
    expect(find.text('Tell Ava when you get in'), findsOneWidget);
    expect(find.text('1 Amir Temur Ave, Tashkent'), findsOneWidget);
    expect(find.text('Comfort'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
  });

  testWidgets("I'm on my way appears once the driver has arrived, and confirms", (
    tester,
  ) async {
    await pump(
      tester,
      const TripState(phase: TripPhase.driverArrived, driver: driverWithPhone),
      arrived: true,
    );
    expect(find.text("I'm on my way"), findsOneWidget);

    await pump(
      tester,
      const TripState(
        phase: TripPhase.driverArrived,
        driver: driverWithPhone,
        riderComingSent: true,
      ),
      arrived: true,
    );
    await tester.pumpAndSettle();
    expect(find.text("I'm on my way"), findsNothing);
    expect(find.text("Ava knows you're on your way"), findsOneWidget);
  });

  testWidgets("I'm on my way is not offered while the driver is still far", (
    tester,
  ) async {
    await pump(
      tester,
      const TripState(
        phase: TripPhase.driverEnRoute,
        driver: driverWithPhone,
        liveEtaSec: 600,
      ),
    );
    expect(find.text("I'm on my way"), findsNothing);
  });
}
