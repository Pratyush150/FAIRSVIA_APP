import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

/// Resolves the rider's current location, falling back to a city center when
/// permission is denied or GPS is unavailable.
class LocationService {
  static const GeoPoint fallback = GeoPoint(25.7743, -80.1937); // Miami, FL

  Future<GeoPoint> currentOrFallback() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return fallback;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return fallback;
      }

      final pos = await Geolocator.getCurrentPosition();
      return GeoPoint(pos.latitude, pos.longitude);
    } catch (_) {
      return fallback;
    }
  }
}
