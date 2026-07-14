import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

/// Resolves the rider's current location, falling back to a city center when
/// permission is denied or GPS is unavailable.
class LocationService {
  static const GeoPoint fallback = GeoPoint(25.7743, -80.1937); // Miami, FL

  /// Dev/testing override. Build with `--dart-define=MOCK_LOCATION=<lat>,<lng>`
  /// to pin the rider's location instead of reading device GPS — useful when
  /// demoing this Florida-only app from elsewhere. Empty (default) = real GPS.
  static const String _mockLocation = String.fromEnvironment('MOCK_LOCATION');

  static GeoPoint? get _mockPoint {
    if (_mockLocation.isEmpty) return null;
    final parts = _mockLocation.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng);
  }

  Future<GeoPoint> currentOrFallback() async {
    final mock = _mockPoint;
    if (mock != null) return mock;
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
