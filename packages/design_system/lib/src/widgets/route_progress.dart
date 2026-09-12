import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// The route split around the vehicle's live position: the part already covered
/// (behind the car) and the part still ahead (from the car forward).
///
/// Drawing only [remaining] in bold makes the route line **shrink behind the
/// car** as it drives — and disappear on arrival — exactly like Uber/Ola. The
/// dimmed [traveled] portion can be drawn faintly (or omitted) so the progress
/// reads clearly.
class RouteSplit {
  const RouteSplit({
    required this.traveled,
    required this.remaining,
    required this.offRouteMeters,
    required this.remainingMeters,
  });

  /// Route points from the start up to the car's projected position.
  final List<LatLng> traveled;

  /// The car's projected position, then every remaining route point to the end.
  final List<LatLng> remaining;

  /// How far the car actually is from the drawn route at the projection point,
  /// in metres. A large value means the car has **left** the route (a signal to
  /// re-route from its real position).
  final double offRouteMeters;

  /// Length of [remaining] in metres — how much road is still ahead of the car.
  /// Falls to ~0 as the car reaches the destination, so the caller can drop the
  /// line entirely on arrival (the "finish line finishing" at the destination).
  final double remainingMeters;
}

/// Total length of a polyline in metres.
double pathLengthMeters(List<LatLng> pts) {
  var total = 0.0;
  for (var i = 0; i < pts.length - 1; i++) {
    total += distanceMeters(pts[i], pts[i + 1]);
  }
  return total;
}

/// Great-circle distance in metres (haversine).
double distanceMeters(LatLng a, LatLng b) {
  const r = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLon = (b.longitude - a.longitude) * math.pi / 180;
  final la1 = a.latitude * math.pi / 180;
  final la2 = b.latitude * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Closest point to [p] on the segment [a]→[b], plus the fraction `t` in [0,1]
/// of how far along the segment it lands. Uses an equirectangular projection
/// (longitude scaled by cos(latitude)) — accurate at street scale.
({LatLng point, double t}) _projectOnSegment(LatLng a, LatLng b, LatLng p) {
  final kx = math.cos(a.latitude * math.pi / 180);
  final ax = a.longitude * kx, ay = a.latitude;
  final bx = b.longitude * kx, by = b.latitude;
  final px = p.longitude * kx, py = p.latitude;
  final dx = bx - ax, dy = by - ay;
  final denom = dx * dx + dy * dy;
  if (denom == 0) return (point: a, t: 0);
  var t = ((px - ax) * dx + (py - ay) * dy) / denom;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final projX = ax + t * dx, projY = ay + t * dy;
  return (point: LatLng(projY, projX / kx), t: t);
}

/// Split [route] at the point on it nearest to the car at [car].
///
/// Finds the single nearest point across every segment, then returns the route
/// before it ([RouteSplit.traveled]) and from it onward ([RouteSplit.remaining],
/// which starts exactly at the projected position so the line begins under the
/// car). [RouteSplit.offRouteMeters] is the car's real distance from that point.
RouteSplit splitRouteAtPoint(List<LatLng> route, LatLng car) {
  if (route.length < 2) {
    return RouteSplit(
      traveled: const [],
      remaining: List<LatLng>.of(route),
      offRouteMeters: 0,
      remainingMeters: pathLengthMeters(route),
    );
  }

  var bestDist = double.infinity;
  var bestIndex = 0; // segment start index i (segment route[i]→route[i+1])
  LatLng bestPoint = route.first;

  for (var i = 0; i < route.length - 1; i++) {
    final proj = _projectOnSegment(route[i], route[i + 1], car);
    final d = distanceMeters(car, proj.point);
    if (d < bestDist) {
      bestDist = d;
      bestIndex = i;
      bestPoint = proj.point;
    }
  }

  final traveled = <LatLng>[
    for (var i = 0; i <= bestIndex; i++) route[i],
    bestPoint,
  ];
  final remaining = <LatLng>[
    bestPoint,
    for (var i = bestIndex + 1; i < route.length; i++) route[i],
  ];

  return RouteSplit(
    traveled: traveled,
    remaining: remaining,
    offRouteMeters: bestDist,
    remainingMeters: pathLengthMeters(remaining),
  );
}

/// Rate-limits live re-routing so a wandering GPS can't hammer the directions
/// API. It fires only when the car is clearly **off the drawn route** AND enough
/// time and movement have passed since the last re-route, AND no fetch is in
/// flight. Changing [leg] (e.g. approach→trip) resets the throttle so the new
/// leg re-routes promptly if needed. Pure/deterministic — inject [now] in tests.
class RerouteGate {
  RerouteGate({
    this.offRouteThresholdMeters = 55,
    this.minInterval = const Duration(seconds: 6),
    this.minMoveMeters = 25,
  });

  /// How far off the line counts as "left the route".
  final double offRouteThresholdMeters;

  /// Minimum gap between two re-routes.
  final Duration minInterval;

  /// Minimum car movement between two re-routes.
  final double minMoveMeters;

  DateTime? _lastAt;
  LatLng? _lastFrom;
  Object? _leg;
  bool _inFlight = false;

  /// Whether to re-route now. Call [begin] before the async fetch and [end]
  /// after it so overlapping requests are suppressed and the throttle advances.
  bool shouldReroute({
    required LatLng from,
    required double offRouteMeters,
    required Object leg,
    DateTime? now,
  }) {
    if (_inFlight) return false;
    if (leg != _leg) {
      _leg = leg;
      _lastAt = null;
      _lastFrom = null;
    }
    if (offRouteMeters < offRouteThresholdMeters) return false;
    final t = now ?? DateTime.now();
    if (_lastAt != null && t.difference(_lastAt!) < minInterval) return false;
    if (_lastFrom != null &&
        distanceMeters(_lastFrom!, from) < minMoveMeters) {
      return false;
    }
    return true;
  }

  void begin() => _inFlight = true;

  /// Mark a fetch finished, advancing the throttle from [from].
  void end(LatLng from, {DateTime? now}) {
    _inFlight = false;
    _lastAt = now ?? DateTime.now();
    _lastFrom = from;
  }
}
