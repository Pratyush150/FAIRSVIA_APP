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
