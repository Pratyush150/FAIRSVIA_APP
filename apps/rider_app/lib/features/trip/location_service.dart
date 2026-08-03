import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

/// Resolves the rider's current location, falling back to a city center when
/// permission is denied or GPS is unavailable.
class LocationService {
  /// City center used when GPS is denied/unavailable. Configurable per build:
  /// `--dart-define=FALLBACK_LOCATION=<lat>,<lng>` (defaults to Miami, FL).
  static final GeoPoint fallback =
      _parsePoint(const String.fromEnvironment('FALLBACK_LOCATION')) ??
          const GeoPoint(25.7743, -80.1937);

  static GeoPoint? _parsePoint(String s) {
    if (s.isEmpty) return null;
    final parts = s.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return GeoPoint(lat, lng);
  }

  /// Dev/testing override. Build with `--dart-define=MOCK_LOCATION=<lat>,<lng>`
  /// to pin the rider's location instead of reading device GPS — useful when
  /// demoing this Florida-only app from elsewhere. Empty (default) = real GPS.
  static const String _mockLocation = String.fromEnvironment('MOCK_LOCATION');

  static GeoPoint? get _mockPoint => _parsePoint(_mockLocation);

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
