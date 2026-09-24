import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/ride_status.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:shared_models/shared_models.dart';

/// The ride's micro-copy: one place decides what each moment of a ride says,
/// so the wording (and the thresholds that switch it) can be checked without
/// pumping a widget.
void main() {
  TripState enRoute({int? eta, AssignedDriver? driver}) => TripState(
        phase: TripPhase.driverEnRoute,
        liveEtaSec: eta,
        driver: driver,
      );

  group('driver on the way', () {
    test('puts who and when in the headline, what to do under it', () {
      final s = RideStatus.of(enRoute(eta: 240));
      expect(s.title, 'Your driver arriving in 4 min');
      expect(s.subtitle, 'Meet at your pickup spot');
    });

    test('switches to "almost here" as the car closes in', () {
      expect(RideStatus.of(enRoute(eta: 240)).title,
          'Your driver arriving in 4 min');
      expect(RideStatus.of(enRoute(eta: 120)).title,
          'Your driver is arriving now');
      expect(RideStatus.of(enRoute(eta: 120)).subtitle, 'Head to your pickup spot');
    });

    test('never counts down to zero minutes', () {
      // "Arriving in 0 min" reads as "should already be here".
      expect(RideStatus.of(enRoute(eta: 5)).title, 'Your driver is arriving now');
      expect(RideStatus.minutesFrom(1), 1);
    });

    test('falls back to the ETA quoted at accept before the first ping', () {
      final s = RideStatus.of(
        enRoute(driver: const AssignedDriver(name: 'Raj', rating: 4.9, etaSec: 300)),
      );
      expect(s.title, 'Raj arriving in 5 min');
    });

    test('promises no time it cannot back up', () {
      final s = RideStatus.of(enRoute());
      expect(s.title, 'Your driver is on the way');
      expect(s.subtitle, isNull);
    });
  });

  test('arrived tells the rider what to do', () {
    const state = TripState(phase: TripPhase.driverArrived);
    final s = RideStatus.of(state);
    expect(s.title, 'Your driver has arrived');
    expect(s.subtitle, 'Meet them at the pickup');
    expect(s.tone, RideStatusTone.success);
  });

  group("uses the driver's first name once it is known", () {
    const bekzod = AssignedDriver(name: 'Bekzod Karimov', rating: 4.9);
    test('on the way / arriving now', () {
      expect(RideStatus.of(enRoute(eta: 240, driver: bekzod)).title,
          'Bekzod arriving in 4 min');
      expect(RideStatus.of(enRoute(eta: 60, driver: bekzod)).title,
          'Bekzod is arriving now');
    });
    test('arrived', () {
      const state =
          TripState(phase: TripPhase.driverArrived, driver: bekzod);
      expect(RideStatus.of(state).title, 'Bekzod has arrived');
    });
    test('never shows a placeholder as a name', () {
      const placeholder = AssignedDriver(name: 'Your driver', rating: 5);
      expect(RideStatus.of(enRoute(eta: 240, driver: placeholder)).title,
          'Your driver arriving in 4 min');
    });
  });

  test('searching says what the system is doing', () {
    const state = TripState(phase: TripPhase.searching);
    final s = RideStatus.of(state);
    expect(s.title, 'Finding your driver');
    expect(s.subtitle, 'Looking for nearby drivers…');
  });

  group('on trip', () {
    test('counts down the time to the destination', () {
      const state =
          TripState(phase: TripPhase.onTrip, liveEtaSec: 1080);
      final s = RideStatus.of(state);
      expect(s.title, 'Ride in progress');
      expect(s.subtitle, '18 min to destination');
    });

    test('becomes "arriving soon" near the end', () {
      const state = TripState(
        phase: TripPhase.onTrip,
        liveEtaSec: 90,
        dropoffAddr: '221B Baker St',
      );
      final s = RideStatus.of(state);
      expect(s.title, 'Arriving soon');
      expect(s.subtitle, '221B Baker St');
    });
  });

  group('completed', () {
    test('shows the total that was actually charged', () {
      const state = TripState(phase: TripPhase.completed, fareFinal: 240);
      final s = RideStatus.of(state);
      expect(s.title, 'Ride completed');
      expect(s.subtitle, '\$240');
    });

    test('shows no fare rather than a fabricated zero', () {
      // A receipt still settling must not tell the rider the ride was free.
      const state = TripState(phase: TripPhase.completed, fareFinal: 0);
      expect(RideStatus.of(state).subtitle, isNull);
    });
  });

  test('the pre-ride phases have no live status of their own', () {
    for (final phase in [
      TripPhase.idle,
      TripPhase.loadingEstimate,
      TripPhase.choosingRide,
      TripPhase.requesting,
      TripPhase.scheduled,
      TripPhase.error,
    ]) {
      expect(RideStatus.of(TripState(phase: phase)).title, isEmpty,
          reason: '$phase should not claim a live ride status');
    }
  });
}
