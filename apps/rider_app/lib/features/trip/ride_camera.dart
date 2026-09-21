import 'package:shared_models/shared_models.dart';

import 'trip_cubit.dart';

/// Who is allowed to move the rider's map camera, and where to.
///
/// Pulled out of the home page as pure functions because the rules are subtle,
/// safety-relevant and were previously spread across three widgets:
///
///  * the rider's own GPS must **never** move the camera during a ride. The
///    person holding the phone is not necessarily the passenger — a ride booked
///    for someone else can have the booker in Delhi and the car in Bangalore —
///    so a GPS fix that recentres the map rips them away from the car they are
///    watching. Driver position comes from the ride, by ride id, over the
///    socket; the viewer's own coordinates are not an input to it.
///  * "Recenter" during a ride means *the car*, not the rider and not a re-fit
///    of the route bounds.
class RideCamera {
  RideCamera._();

  /// Street-level zoom a recenter restores. Matches the map's initial zoom, so
  /// tapping recenter after a pinch or a route fit always lands the rider back
  /// at the same readable scale rather than wherever they left the camera.
  static const double recenterZoom = 16;

  /// Phases where a driver is on the map and the rider is watching them move.
  static bool tracksDriver(TripState state) =>
      state.driverLocation != null &&
      (state.phase == TripPhase.driverEnRoute ||
          state.phase == TripPhase.driverArrived ||
          state.phase == TripPhase.onTrip);

  /// Whether a ride is live enough that the map belongs to it. Covers the
  /// window from "looking for a driver" to the completion sheet — including
  /// the gap before the first driver ping, where [tracksDriver] is still false
  /// but the camera is already framing the route.
  static bool rideOwnsCamera(TripState state) => switch (state.phase) {
        TripPhase.idle ||
        TripPhase.loadingEstimate ||
        TripPhase.error =>
          false,
        _ => true,
      };

  /// Whether a fresh fix from the phone's own GPS may move the camera.
  ///
  /// Only when no ride owns the map. This is the rule that keeps a ride booked
  /// for somebody else watchable: the booker's location updates their pickup
  /// pin and nothing else.
  static bool myLocationMayMoveCamera(TripState state) =>
      !rideOwnsCamera(state);

  /// Where the Precise/Recenter button should send the camera.
  ///
  /// During live tracking that is the latest driver position — even if the
  /// rider panned away, even if they just came back from the app being
  /// backgrounded, and regardless of where the rider's own phone is. Returns
  /// null when the answer is "re-fit whatever the ride is framing" (before a
  /// driver exists) or "the rider's own position" (no ride at all); the caller
  /// distinguishes those with [rideOwnsCamera].
  static GeoPoint? recenterTarget(TripState state) =>
      tracksDriver(state) ? state.driverLocation : null;
}
