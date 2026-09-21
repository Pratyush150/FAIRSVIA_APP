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
    test('states the ETA under the headline, not as it', () {
      final s = RideStatus.of(enRoute(eta: 240));
      expect(s.title, 'Your driver is on the way');
      expect(s.subtitle, 'Arriving in 4 min');
    });

    test('switches to "almost here" as the car closes in', () {
      expect(RideStatus.of(enRoute(eta: 240)).title,
          'Your driver is on the way');
      expect(RideStatus.of(enRoute(eta: 120)).title,
          'Your driver is almost here');
      expect(RideStatus.of(enRoute(eta: 120)).subtitle, 'Arriving in 2 min');
    });

    test('never counts down to zero minutes', () {
      // "Arriving in 0 min" reads as "should already be here".
      expect(RideStatus.of(enRoute(eta: 5)).subtitle, 'Arriving in 1 min');
      expect(RideStatus.minutesFrom(1), 1);
    });

    test('falls back to the ETA quoted at accept before the first ping', () {
      final s = RideStatus.of(
        enRoute(driver: const AssignedDriver(name: 'Raj', rating: 4.9, etaSec: 300)),
      );
      expect(s.subtitle, 'Arriving in 5 min');
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
    expect(s.subtitle, 'Please meet your driver');
    expect(s.tone, RideStatusTone.success);
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
