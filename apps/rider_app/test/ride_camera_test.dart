import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/ride_camera.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:shared_models/shared_models.dart';

/// Who owns the map camera.
///
/// The rule these tests exist for: a ride booked for somebody else can have
/// the person holding the phone hundreds of miles from the car. Their GPS must
/// never move the camera, and "Recenter" must mean the car.
void main() {
  const delhi = GeoPoint(28.6139, 77.2090); // the booking user
  const bangalore = GeoPoint(12.9716, 77.5946); // the car

  TripState tracking(TripPhase phase) =>
      const TripState().copyWith(phase: phase, driverLocation: bangalore);

  group('a ride owns the camera', () {
    test('while a driver is being tracked', () {
      for (final phase in [
        TripPhase.driverEnRoute,
        TripPhase.driverArrived,
        TripPhase.onTrip,
      ]) {
        expect(
          RideCamera.tracksDriver(tracking(phase)),
          isTrue,
          reason: '$phase',
        );
      }
    });

    test('but not before a driver has reported a position', () {
      // Matched, no ping yet: nothing to follow, so the camera keeps framing
      // the route rather than chasing a null.
      const matched = TripState(phase: TripPhase.driverEnRoute);
      expect(RideCamera.tracksDriver(matched), isFalse);
      // The ride still owns the camera, though — the rider's GPS must not
      // grab it back in the gap before the first ping.
      expect(RideCamera.rideOwnsCamera(matched), isTrue);
    });

    test('and not at all when there is no ride', () {
      for (final phase in [
        TripPhase.idle,
        TripPhase.loadingEstimate,
        TripPhase.error,
      ]) {
        expect(
          RideCamera.rideOwnsCamera(TripState(phase: phase)),
          isFalse,
          reason: '$phase',
        );
      }
    });
  });

  group("the viewer's own GPS", () {
    test('moves the camera only when no ride is on screen', () {
      expect(RideCamera.myLocationMayMoveCamera(const TripState()), isTrue);
    });

    test('never moves the camera during a ride', () {
      // THE regression this guards: a booking user in Delhi opening a ride
      // running in Bangalore. Their first GPS fix used to yank the camera
      // 1,700 km away from the car they were watching.
      for (final phase in [
        TripPhase.choosingRide,
        TripPhase.requesting,
        TripPhase.searching,
        TripPhase.driverEnRoute,
        TripPhase.driverArrived,
        TripPhase.onTrip,
        TripPhase.completed,
      ]) {
        expect(
          RideCamera.myLocationMayMoveCamera(tracking(phase)),
          isFalse,
          reason: '$phase must not hand the camera to the viewer\'s GPS',
        );
      }
    });
  });

  group('recenter', () {
    test('targets the latest driver position during a ride', () {
      final target = RideCamera.recenterTarget(tracking(TripPhase.onTrip));
      expect(target, bangalore);
      // Explicitly NOT the phone holding the app.
      expect(target, isNot(delhi));
    });

    test('follows the car as it moves, not the position it started at', () {
      const moved = GeoPoint(12.99, 77.61);
      final state = tracking(TripPhase.onTrip).copyWith(driverLocation: moved);
      expect(RideCamera.recenterTarget(state), moved);
    });

    test('defers to the caller when there is no car to centre on', () {
      expect(RideCamera.recenterTarget(const TripState()), isNull);
      expect(
        RideCamera.recenterTarget(const TripState(phase: TripPhase.searching)),
        isNull,
      );
    });
  });
}
