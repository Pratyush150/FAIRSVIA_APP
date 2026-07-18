import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Dev/testing override. Build with `--dart-define=MOCK_LOCATION=<lat>,<lng>`
/// to pin the driver's location instead of reading device GPS — needed to test
/// the driver flow on a phone that isn't physically in the service area (this
/// is a Florida-only backend). Empty (default) = real GPS. Mirrors the rider
/// app's LocationService.
const String _mockLocation = String.fromEnvironment('MOCK_LOCATION');

({double lat, double lng})? get _mockPoint {
  if (_mockLocation.isEmpty) return null;
  final parts = _mockLocation.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) return null;
  return (lat: lat, lng: lng);
}

/// Ensures location permission and returns a position stream for the driver's
/// live location while online.
Future<bool> ensureLocationPermission() async {
  if (_mockPoint != null) return true; // dev override — no device GPS needed
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

Position _mockPositionAt(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 90,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Stream<Position> driverPositionStream() {
  final mock = _mockPoint;
  if (mock != null) {
    // Emit immediately, then every 4s, so the backend registers the driver
    // online and keeps presence fresh (the geo index expects periodic updates).
    return Stream<Position>.multi((controller) {
      controller.add(_mockPositionAt(mock.lat, mock.lng));
      final timer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => controller.add(_mockPositionAt(mock.lat, mock.lng)),
      );
      controller.onCancel = timer.cancel;
    });
  }
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  );
}
