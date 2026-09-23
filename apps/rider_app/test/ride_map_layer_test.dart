import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/map_utils.dart';
import 'package:rider_app/features/trip/ride_map_layer.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:shared_models/shared_models.dart';

/// What the map draws, as pure data — no platform view required.
void main() {
  const me = GeoPoint(12.90, 77.50);
  const pickup = GeoPoint(12.9716, 77.5946);
  const dropoff = GeoPoint(12.9352, 77.6245);
  const car = GeoPoint(12.9800, 77.6000);

  RideMapLayer layer(TripState state, {TripPhase? followed, bool suppressed = false}) =>
      RideMapLayer(
        state: state,
        myLocation: me,
        followedPhase: followed,
        fitSuppressed: suppressed,
      );

  AppMapMarker? of(List<AppMapMarker> ms, MapMarkerKind kind) {
    for (final m in ms) {
      if (m.kind == kind) return m;
    }
    return null;
  }

  group('markers', () {
    test('show the rider before a driver exists, and drop them after', () {
      const idle = TripState(pickup: pickup, dropoff: dropoff);
      expect(of(layer(idle).markers, MapMarkerKind.me), isNotNull);

      const enRoute = TripState(
        phase: TripPhase.driverEnRoute,
        pickup: pickup,
        dropoff: dropoff,
        driverLocation: car,
      );
      // Once the car is what matters, the rider's own dot is clutter next to
      // the pickup pin.
      expect(of(layer(enRoute).markers, MapMarkerKind.me), isNull);
      expect(of(layer(enRoute).markers, MapMarkerKind.driver), isNotNull);
    });

    test('carry the driver heading so a parked car keeps pointing its way', () {
      const state = TripState(
        phase: TripPhase.onTrip,
        pickup: pickup,
        dropoff: dropoff,
        driverLocation: car,
        driverHeading: 137,
      );
      expect(of(layer(state).markers, MapMarkerKind.driver)!.heading, 137);
    });

    test('flag a stale driver position rather than drawing it as live', () {
      const fresh = TripState(
        phase: TripPhase.onTrip,
        driverLocation: car,
      );
      expect(of(layer(fresh).markers, MapMarkerKind.driver)!.stale, isFalse);

      final stale = fresh.copyWith(driverStale: true);
      expect(of(layer(stale).markers, MapMarkerKind.driver)!.stale, isTrue);
    });
  });

  group('the live leg', () {
    test('is the approach while the driver comes to the pickup', () {
      expect(layer(const TripState(phase: TripPhase.driverEnRoute)).legKey,
          'approach');
      expect(layer(const TripState(phase: TripPhase.driverArrived)).legKey,
          'approach');
    });

    test('becomes the trip once it starts, and is nothing before or after', () {
      expect(layer(const TripState(phase: TripPhase.onTrip)).legKey, 'trip');
      expect(layer(const TripState()).legKey, isNull);
      expect(layer(const TripState(phase: TripPhase.completed)).legKey, isNull);
    });
  });

  group('the drawn line', () {
    test('has nothing left once the driver has arrived', () {
      // The approach is over; leaving its line up draws a route to a car that
      // is already there.
      const arrived = TripState(
        phase: TripPhase.driverArrived,
        pickup: pickup,
        dropoff: dropoff,
        driverLocation: car,
        driverRoutePolyline: 'ynbnAkxqxMpBqE', // any 2-point line
      );
      expect(layer(arrived).route, isEmpty);
    });

    test('a leg with no polyline draws nothing rather than guessing', () {
      const state = TripState(phase: TripPhase.onTrip, driverLocation: car);
      expect(layer(state).route, isEmpty);
    });
  });

  group('the camera box', () {
    test('is nothing at all without both ends of the trip', () {
      expect(layer(const TripState(pickup: pickup)).fitBounds, isNull);
      expect(layer(const TripState(dropoff: dropoff)).fitBounds, isNull);
    });

    test('frames pickup and dropoff before a driver is on the way', () {
      const state = TripState(
        phase: TripPhase.choosingRide,
        pickup: pickup,
        dropoff: dropoff,
      );
      final b = layer(state).fitBounds!;
      expect(b, hasLength(2));
      expect(b.first, MapUtils.toLatLng(pickup));
      expect(b.last, MapUtils.toLatLng(dropoff));
    });

    test('opens a box around the pickup when the car has all but arrived', () {
      // Car essentially on top of the pickup: a bounds fit here would zoom to
      // maximum, so a fixed box is framed instead.
      const state = TripState(
        phase: TripPhase.driverArrived,
        pickup: pickup,
        dropoff: dropoff,
        driverLocation: pickup,
      );
      final b = layer(state).fitBounds!;
      expect(MapUtils.spanMeters(b),
          greaterThan(RideMapLayer.minFitSpanM));
    });

    /// Regression: a malformed approach polyline decodes to points at (0, 0)
    /// — "null island", in the Gulf of Guinea. The camera framed everything
    /// from there to Pune, so a rider watching their driver approach saw a map
    /// of the whole world. There was a guard for a too-small span but none for
    /// a too-large one.
    test('throws away a camera box that spans the planet', () {
      // Decodes to [(0, 0), (18.5204, 73.8567)] — null island to the Pune
      // pickup. That is ~7,700 km across: the old code framed all of it,
      // because the only guard was for a span that was too *small*.
      const nullIsland = '??og`pBkcxaM';
      const state = TripState(
        phase: TripPhase.driverEnRoute,
        pickup: pickup,
        dropoff: dropoff,
        driverRoutePolyline: nullIsland,
      );
      final b = layer(state).fitBounds!;
      final span = MapUtils.spanMeters(b);
      expect(span, lessThan(RideMapLayer.maxFitSpanM),
          reason: 'must not frame null island to the pickup');
      expect(span, greaterThan(RideMapLayer.minFitSpanM));
      // It falls back to a box around the pickup, so the rider still sees
      // where they are standing.
      for (final p in b) {
        expect(MapUtils.spanMeters([p, MapUtils.toLatLng(pickup)]),
            lessThan(RideMapLayer.maxFitSpanM));
      }
    });

    test('stops re-fitting once the phase has been framed, so follow can run',
        () {
      const state = TripState(
        phase: TripPhase.onTrip,
        pickup: pickup,
        dropoff: dropoff,
        driverLocation: car,
      );
      // First frame of the phase: fit it.
      expect(layer(state).cameraFitBounds, isNotNull);
      // Already framed: hand the camera to follow mode rather than re-zooming
      // the map a second at a time on every GPS ping.
      expect(layer(state, followed: TripPhase.onTrip).cameraFitBounds, isNull);
    });

    test('yields for the frame that forces a re-fit', () {
      const state = TripState(
        phase: TripPhase.choosingRide,
        pickup: pickup,
        dropoff: dropoff,
      );
      expect(layer(state, suppressed: true).cameraFitBounds, isNull);
    });
  });
}
