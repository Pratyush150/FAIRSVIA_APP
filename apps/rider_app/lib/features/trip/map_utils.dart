import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_models/shared_models.dart';

/// Conversions between our plain [GeoPoint] and flutter_map's [LatLng], plus
/// polyline decoding for the route overlay. (Camera bounds-fitting now lives in
/// the shared AppMap widget.)
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
}
