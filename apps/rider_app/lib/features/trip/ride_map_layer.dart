import 'package:design_system/design_system.dart';
import 'package:shared_models/shared_models.dart';

import 'map_utils.dart';
import 'ride_camera.dart';
import 'trip_cubit.dart';

/// Everything the map draws for one frame of a ride: the markers, the route
/// line, and the box the camera should frame.
///
/// A value object built fresh each build from the trip state plus the little
/// bit of view state that legitimately belongs to the page (the rider's own
/// position, the locally re-routed line, whether a fit is being suppressed).
/// Pulling it out of the page's State means these rules — which leg is live,
/// which line to draw, what to frame when the car has nearly arrived — can be
/// unit-tested directly instead of only through a map widget that needs a
/// platform view to render.
class RideMapLayer {
  const RideMapLayer({
    required this.state,
    required this.myLocation,
    this.liveRoutePolyline,
    this.liveRouteLeg,
    this.fitSuppressed = false,
    this.followedPhase,
  });

  final TripState state;

  /// The rider's own position. Drawn as the blue dot before a driver exists;
  /// never used to place the car or move the camera (see [RideCamera]).
  final GeoPoint myLocation;

  /// A road route this app re-fetched after the car left the drawn line, and
  /// the leg it belongs to — so a line from the previous leg is never drawn on
  /// this one.
  final String? liveRoutePolyline;
  final String? liveRouteLeg;

  /// Set for one frame to hand the map a null fit, so re-supplying the same
  /// bounds next frame counts as a change and re-fits the camera.
  final bool fitSuppressed;

  /// The phase whose opening frame has already been shown. While it matches
  /// the live phase the camera follows the car instead of re-fitting.
  final TripPhase? followedPhase;

  /// Below this car↔pickup span the two points are effectively on top of each
  /// other and a bounds fit would zoom the map to its maximum; frame a fixed
  /// [arrivalBoxHalfSpanM] box around the pickup instead.
  static const double minFitSpanM = 60;
  static const double arrivalBoxHalfSpanM = 125; // ~250 m box

  /// The active leg for re-routing: 'approach' (driver→pickup) while the
  /// driver is on the way, 'trip' (→destination) once moving, else null.
  String? get legKey {
    if (state.phase == TripPhase.driverEnRoute ||
        state.phase == TripPhase.driverArrived) {
      return 'approach';
    }
    if (state.phase == TripPhase.onTrip) return 'trip';
    return null;
  }

  /// The planned (or freshly re-routed) line for the current leg, untrimmed.
  List<LatLng> get plannedRoute {
    final leg = legKey;
    // Prefer a freshly re-routed line for the current leg — the road the
    // driver actually took — over the route planned at booking/accept. The
    // server's own recompute wins: it is also what its live ETA is measured
    // against, so taking it keeps the drawn line and the "N min" agreeing, and
    // spares us a duplicate routing call.
    if (leg != null && state.liveRouteLeg == leg) {
      final pushed = state.liveRoutePolyline;
      if (pushed != null && pushed.isNotEmpty) {
        final live = MapUtils.decodePolyline(pushed);
        if (live.length >= 2) return live;
      }
    }
    if (leg != null && liveRoutePolyline != null && liveRouteLeg == leg) {
      final live = MapUtils.decodePolyline(liveRoutePolyline!);
      if (live.length >= 2) return live;
    }
    // While the driver is on the way, draw THEIR route to the pickup (the
    // approach leg) so the line matches where the car is actually going; once
    // the trip starts, fall back to the pickup→destination trip route.
    final approaching = leg == 'approach';
    final approachRoute = state.driverRoutePolyline;
    // After a cold-start restore there is no estimate; the trip carries its
    // own route polyline, so fall back to that rather than drawing nothing.
    final encoded =
        (approaching && approachRoute != null && approachRoute.isNotEmpty)
            ? approachRoute
            : (state.estimate?.polyline ?? state.trip?.routePolyline);
    if (encoded == null || encoded.isEmpty) return const [];
    return MapUtils.decodePolyline(encoded);
  }

  /// The line to draw, trimmed behind the car so the route "shrinks" as it is
  /// driven and has nothing left to show once the driver has arrived.
  List<LatLng> get route {
    final approaching = legKey == 'approach';
    final planned = plannedRoute;
    if (planned.isEmpty) return planned;
    if (state.phase == TripPhase.driverArrived && approaching) return const [];
    final car = state.driverLocation;
    if (car != null &&
        (state.phase == TripPhase.driverEnRoute ||
            state.phase == TripPhase.onTrip)) {
      return routeRemainingPath(planned, MapUtils.toLatLng(car));
    }
    return planned;
  }

  List<AppMapMarker> get markers {
    final out = <AppMapMarker>[];
    // Pins sit on the routed road ends (not the raw geocode, which can land in
    // water or inside a block) whenever a route is known.
    final tripRoute = MapUtils.decodePolyline(
      state.estimate?.polyline ?? state.trip?.routePolyline ?? '',
    );
    if (state.pickup != null) {
      out.add(AppMapMarker(
        point: tripRoute.length >= 2
            ? tripRoute.first
            : MapUtils.toLatLng(state.pickup!),
        kind: MapMarkerKind.pickup,
        label: 'Pickup',
      ));
    }
    if (state.dropoff != null) {
      out.add(AppMapMarker(
        point: tripRoute.length >= 2
            ? tripRoute.last
            : MapUtils.toLatLng(state.dropoff!),
        kind: MapMarkerKind.dropoff,
        label: 'Destination',
      ));
    }
    if (state.driverLocation != null) {
      out.add(AppMapMarker(
        point: MapUtils.toLatLng(state.driverLocation!),
        kind: MapMarkerKind.driver,
        label: 'Driver',
        // Pings have stopped: keep the last known position on the map but draw
        // it faded, so "where the car was" never reads as "where the car is".
        stale: state.driverStale,
        // Last reported compass heading, so the car keeps pointing the way it
        // was going even while pings pause (AppMap otherwise derives it from
        // movement and a stale/parked car would spin to 0°).
        heading: state.driverHeading,
      ));
    }
    // "You are here": before a driver is assigned the rider's own position is
    // the anchor of the map (Uber's blue dot). Once on the way it would only
    // clutter the pickup pin, so it is dropped for the live-tracking phases.
    if (state.phase.index <= TripPhase.searching.index ||
        state.phase == TripPhase.error) {
      out.add(AppMapMarker(
        point: MapUtils.toLatLng(myLocation),
        kind: MapMarkerKind.me,
      ));
    }
    return out;
  }

  /// What the camera frames, or null to leave it alone.
  ///
  /// The camera frames the ride once when a phase begins, then hands over to
  /// follow mode. Re-fitting on every driver ping would re-zoom the map a
  /// second at a time; not fitting at all would leave the rider looking at the
  /// wrong part of the city when the phase changes.
  List<LatLng>? get cameraFitBounds {
    if (fitSuppressed) return null;
    if (RideCamera.tracksDriver(state) && followedPhase == state.phase) {
      return null;
    }
    return fitBounds;
  }

  /// The box that frames the ride right now: the driver→pickup leg during the
  /// approach, car + pickup (or a fixed box around it) on arrival, otherwise
  /// pickup→dropoff.
  List<LatLng>? get fitBounds {
    // Prefer the estimate's endpoints; after a cold-start restore there is no
    // estimate, so frame the restored trip's pickup/dropoff instead.
    final pickup = state.estimate?.pickup ?? state.pickup;
    final dropoff = state.estimate?.dropoff ?? state.dropoff;
    if (pickup == null || dropoff == null) return null;
    final pickupLL = MapUtils.toLatLng(pickup);
    final approaching = state.phase == TripPhase.driverEnRoute ||
        state.phase == TripPhase.driverArrived;
    List<LatLng> bounds;
    final approachRoute = state.driverRoutePolyline;
    final approachPts = (approaching && approachRoute != null)
        ? MapUtils.decodePolyline(approachRoute)
        : const <LatLng>[];
    if (state.phase == TripPhase.driverArrived) {
      final car = state.driverLocation != null
          ? MapUtils.toLatLng(state.driverLocation!)
          : (approachPts.isNotEmpty ? approachPts.first : pickupLL);
      bounds = [car, pickupLL];
    } else if (approaching && approachPts.length >= 2) {
      bounds = [approachPts.first, approachPts.last];
    } else {
      bounds = [pickupLL, MapUtils.toLatLng(dropoff)];
    }
    if (MapUtils.spanMeters(bounds) < minFitSpanM) {
      bounds = MapUtils.boxAround(pickupLL, arrivalBoxHalfSpanM);
    }
    return bounds;
  }
}
