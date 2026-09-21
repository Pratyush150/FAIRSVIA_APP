import 'dart:math' as math;

import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_models/shared_models.dart';

/// Conversions between our plain [GeoPoint] and flutter_map's [LatLng], plus
/// polyline decoding for the route overlay. (Camera bounds-fitting now lives in
/// the shared AppMap widget.)
class MapUtils {
  MapUtils._();

  static const double _mPerDegLat = 111320.0;

  static LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

  static List<LatLng> decodePolyline(String encoded) {
    if (encoded.isEmpty) return const [];
    return PolylinePoints()
        .decodePolyline(encoded)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
  }

  /// Diagonal of the bounding box around [pts] in metres (0 for one point).
  /// Used to spot a near-degenerate camera fit (car on top of the pickup),
  /// which the map SDK would otherwise zoom to its maximum.
  static double spanMeters(List<LatLng> pts) {
    if (pts.isEmpty) return 0;
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    final midLat = (minLat + maxLat) / 2 * math.pi / 180;
    final dy = (maxLat - minLat) * _mPerDegLat;
    final dx = (maxLng - minLng) * _mPerDegLat * math.cos(midLat);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// A square box of `2 * halfSpanM` metres a side centred on [c], as the two
  /// corners AppMap's `fitBounds` expects.
  static List<LatLng> boxAround(LatLng c, double halfSpanM) {
    final dLat = halfSpanM / _mPerDegLat;
    final dLng =
        halfSpanM / (_mPerDegLat * math.cos(c.latitude * math.pi / 180));
    return [
      LatLng(c.latitude - dLat, c.longitude - dLng),
      LatLng(c.latitude + dLat, c.longitude + dLng),
    ];
  }
}
