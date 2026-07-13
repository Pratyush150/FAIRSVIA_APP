import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_models/shared_models.dart';

/// Conversions between our plain [GeoPoint] and google_maps [LatLng], plus
/// polyline decoding and bounds fitting.
class MapUtils {
  MapUtils._();

  static LatLng toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

  static List<LatLng> decodePolyline(String encoded) {
    if (encoded.isEmpty) return const [];
    return PolylinePoints()
        .decodePolyline(encoded)
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
  }

  /// Bounding box that contains all [points]. Assumes a non-empty list.
  static LatLngBounds boundsFor(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final p in points) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}
