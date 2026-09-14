import 'dart:math' as math;

import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:latlong2/latlong.dart';

/// Decode a Google/OSRM-style encoded polyline into map points for a route
/// overlay. Shared by rider + driver so route drawing is identical in both.
List<LatLng> decodePolyline(String encoded) {
  if (encoded.isEmpty) return const [];
  return PolylinePoints()
      .decodePolyline(encoded)
      .map((p) => LatLng(p.latitude, p.longitude))
      .toList();
}

/// Great-circle distance in metres.
double distanceMeters(LatLng a, LatLng b) {
  const r = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final la1 = a.latitude * math.pi / 180;
  final la2 = b.latitude * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(la1) * math.cos(la2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Total length of [route] in metres.
double routeLengthMeters(List<LatLng> route) {
  var total = 0.0;
  for (var i = 0; i + 1 < route.length; i++) {
    total += distanceMeters(route[i], route[i + 1]);
  }
  return total;
}

/// Metres still to drive along [route] from the position [at]: [at] is
/// projected onto the nearest route segment, and the remaining length from
/// that projection to the end of the route is returned. Used for the live
/// "Arriving in N min" / "N mi to go" readouts that update with every GPS
/// ping instead of freezing at the match-time estimate.
double routeRemainingMeters(List<LatLng> route, LatLng at) {
  if (route.length < 2) return 0;
  var bestD = double.infinity;
  var bestSeg = 0;
  var bestT = 0.0;
  for (var i = 0; i + 1 < route.length; i++) {
    final a = route[i], b = route[i + 1];
    // Equirectangular projection is plenty for the ~km scale of a ride.
    final cosLat = math.cos(a.latitude * math.pi / 180);
    final ax = 0.0, ay = 0.0;
    final bx = (b.longitude - a.longitude) * cosLat;
    final by = b.latitude - a.latitude;
    final px = (at.longitude - a.longitude) * cosLat;
    final py = at.latitude - a.latitude;
    final len2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay);
    var t = len2 == 0 ? 0.0 : ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / len2;
    t = t.clamp(0.0, 1.0);
    final qx = ax + t * (bx - ax), qy = ay + t * (by - ay);
    final d = math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
    if (d < bestD) {
      bestD = d;
      bestSeg = i;
      bestT = t;
    }
  }
  final a = route[bestSeg], b = route[bestSeg + 1];
  final proj = LatLng(
    a.latitude + bestT * (b.latitude - a.latitude),
    a.longitude + bestT * (b.longitude - a.longitude),
  );
  var remaining = distanceMeters(proj, b);
  for (var i = bestSeg + 1; i + 1 < route.length; i++) {
    remaining += distanceMeters(route[i], route[i + 1]);
  }
  return remaining;
}

/// The part of [route] still ahead of [at]: the projection of [at] onto its
/// nearest segment followed by the remaining vertices. Drawing this instead
/// of the full route makes the line "eat" behind the car the way Uber's does.
List<LatLng> routeRemainingPath(List<LatLng> route, LatLng at) {
  if (route.length < 2) return route;
  var bestD = double.infinity;
  var bestSeg = 0;
  var bestT = 0.0;
  for (var i = 0; i + 1 < route.length; i++) {
    final a = route[i], b = route[i + 1];
    final cosLat = math.cos(a.latitude * math.pi / 180);
    final bx = (b.longitude - a.longitude) * cosLat;
    final by = b.latitude - a.latitude;
    final px = (at.longitude - a.longitude) * cosLat;
    final py = at.latitude - a.latitude;
    final len2 = bx * bx + by * by;
    var t = len2 == 0 ? 0.0 : (px * bx + py * by) / len2;
    t = t.clamp(0.0, 1.0);
    final qx = t * bx, qy = t * by;
    final d = math.sqrt((px - qx) * (px - qx) + (py - qy) * (py - qy));
    if (d < bestD) {
      bestD = d;
      bestSeg = i;
      bestT = t;
    }
  }
  final a = route[bestSeg], b = route[bestSeg + 1];
  final proj = LatLng(
    a.latitude + bestT * (b.latitude - a.latitude),
    a.longitude + bestT * (b.longitude - a.longitude),
  );
  return [proj, ...route.sublist(bestSeg + 1)];
}
