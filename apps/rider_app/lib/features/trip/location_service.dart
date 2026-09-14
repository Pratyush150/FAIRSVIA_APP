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

  /// True when the app currently holds foreground (or always) location access.
  Future<bool> hasPermission() async {
    if (_mockPoint != null) return true;
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  /// Ask for location access. Location is **required** to book a ride, so this
  /// prompts, and if the user has permanently denied it, opens the app's system
  /// settings so they can enable it. Returns whether access is granted after.
  Future<bool> requestPermission() async {
    if (_mockPoint != null) return true;
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      p = await Geolocator.checkPermission();
    }
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  /// Resolve the rider's location. Prefers a fresh fix, but uses the phone's
  /// **last known fix immediately** if a fresh one can't be had quickly (e.g.
  /// indoors) — so the map shows where the rider actually is, not the Miami
  /// fallback. Only drops to [fallback] when there is genuinely no location.
  Future<GeoPoint> currentOrFallback() async {
    final mock = _mockPoint;
    if (mock != null) return mock;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return await _lastKnownOr(fallback);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return await _lastKnownOr(fallback);
      }

      // Instant cached fix (works indoors); refine with a fresh one but never
      // hang or fall back to Miami while a real position exists.
      final cached = await _lastKnown();
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        return GeoPoint(pos.latitude, pos.longitude);
      } catch (_) {
        return cached ?? fallback;
      }
    } catch (_) {
      return await _lastKnownOr(fallback);
    }
  }

  /// A live stream of the rider's position (real GPS), for keeping the map on
  /// the phone's actual location and snapping to the first real fix once GPS
  /// resolves — so the map doesn't sit on the fallback until a manual recenter.
  /// Emits nothing when mocked/denied (the caller keeps its resolved position).
  Stream<GeoPoint> positionStream() {
    if (_mockPoint != null) return const Stream.empty();
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).map((p) => GeoPoint(p.latitude, p.longitude));
  }

  Future<GeoPoint?> _lastKnown() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : GeoPoint(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<GeoPoint> _lastKnownOr(GeoPoint fb) async => (await _lastKnown()) ?? fb;
}
