import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:design_system/design_system.dart' show AppBrand;
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

/// Outcome of a location-access check. Anything but [granted] means the driver
/// must NOT be flipped online: they'd look online but never stream GPS, so they
/// never enter the dispatch geo index and never receive an offer.
enum LocationAccess {
  granted,

  /// Permission granted but iOS 14+/Android 12+ "Precise Location" is off:
  /// fixes are ~1–5 km off, useless for dispatch, pickup and metering.
  reduced,

  /// Permission denied this time; the OS may ask again on the next attempt.
  denied,

  /// Permanently denied — only the app's Settings page can restore it.
  deniedForever,

  /// Device location services are switched off system-wide.
  servicesOff,
}

/// Signature for the pre-online location check, injectable into the cubit so
/// tests can stub it without touching the geolocator plugin.
typedef LocationAccessCheck = Future<LocationAccess> Function();

/// Checks (and, if merely "denied", requests) location access. Call BEFORE
/// going online so a driver without GPS never ends up online-but-invisible.
Future<LocationAccess> checkLocationAccess() async {
  if (_mockPoint != null) return LocationAccess.granted; // dev override
  // Browser geolocation needs HTTPS and isn't available in the web preview;
  // going online there is UI-only (streaming is skipped by the page).
  if (kIsWeb) return LocationAccess.granted;
  if (!await Geolocator.isLocationServiceEnabled()) {
    return LocationAccess.servicesOff;
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  switch (permission) {
    case LocationPermission.always:
    case LocationPermission.whileInUse:
      return _preciseOrReduced();
    case LocationPermission.deniedForever:
      return LocationAccess.deniedForever;
    case LocationPermission.denied:
    case LocationPermission.unableToDetermine:
      return LocationAccess.denied;
  }
}

/// Whether asking for location now would put the OS permission dialog on
/// screen: access is undecided (iOS "not determined"), or on Android it was
/// refused once and may be asked again. The RideVela priming screen goes in
/// front of exactly that dialog, so the driver knows why before the OS asks.
/// Never true in mock-location or web builds (no OS dialog there).
Future<bool> locationPromptPending() async {
  if (_mockPoint != null || kIsWeb) return false;
  try {
    return await Geolocator.checkPermission() == LocationPermission.denied;
  } catch (_) {
    return false;
  }
}

/// Current location access WITHOUT asking for anything: no OS dialog, no
/// temporary-precision prompt. Used to notice a fix made in Settings when the
/// app comes back to the foreground.
Future<LocationAccess> currentLocationAccess() async {
  if (_mockPoint != null || kIsWeb) return LocationAccess.granted;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.servicesOff;
    }
    switch (await Geolocator.checkPermission()) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        try {
          if (await Geolocator.getLocationAccuracy() ==
              LocationAccuracyStatus.reduced) {
            return LocationAccess.reduced;
          }
        } catch (_) {
          // No accuracy API on this platform: full accuracy.
        }
        return LocationAccess.granted;
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationAccess.denied;
    }
  } catch (_) {
    return LocationAccess.denied;
  }
}

/// Opens the fix for [access] in the OS: the location-services page when GPS
/// is switched off system-wide, otherwise this app's own settings page (where
/// the permission and Precise Location live).
Future<bool> openLocationFix(LocationAccess access) async {
  try {
    return access == LocationAccess.servicesOff
        ? await Geolocator.openLocationSettings()
        : await Geolocator.openAppSettings();
  } catch (_) {
    return false;
  }
}

/// iOS 14+ / Android 12+: the user may have granted only approximate
/// location. Ask once for temporary full accuracy (needs the
/// NSLocationTemporaryUsageDescriptionDictionary "PreciseRide" purpose key);
/// if it is still reduced, going online must be refused.
Future<LocationAccess> _preciseOrReduced() async {
  try {
    var acc = await Geolocator.getLocationAccuracy();
    if (acc == LocationAccuracyStatus.reduced) {
      acc = await Geolocator.requestTemporaryFullAccuracy(
        purposeKey: 'PreciseRide',
      );
    }
    if (acc == LocationAccuracyStatus.reduced) return LocationAccess.reduced;
  } catch (_) {
    // Platforms without the API (older OS, web) report full accuracy.
  }
  return LocationAccess.granted;
}

/// User-facing explanation for a failed [checkLocationAccess].
String locationAccessMessage(LocationAccess access) {
  switch (access) {
    case LocationAccess.granted:
      return '';
    case LocationAccess.reduced:
      return 'Precise Location is off. Turn it on in Settings so riders can '
          'find you and trips are metered correctly';
    case LocationAccess.servicesOff:
      return 'Turn on location services to go online';
    case LocationAccess.deniedForever:
      return 'Location permission is off. Allow it in Settings to go online';
    case LocationAccess.denied:
      return 'Location permission is required to go online';
  }
}

/// Ensures location permission and returns a position stream for the driver's
/// live location while online.
Future<bool> ensureLocationPermission() async =>
    await checkLocationAccess() == LocationAccess.granted;

Position _mockPositionAt(double lat, double lng, {double heading = 90}) =>
    Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: heading,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

// ── Simulated driving (mock mode only) ──────────────────────────────────────
// Walks the car ALONG THE ROAD ROUTE (the decoded polyline the backend already
// computes) at a steady speed — so it tracks streets like Uber/Ola instead of
// sliding in a straight line across buildings and water.
const int _tickMs = 400;
({double lat, double lng})? _simCurrent;
double _simHeading = 90;

List<({double lat, double lng})> _simPath = const [];
int _simIdx = 0;
/// Dev/demo override for the simulated car's speed in m/s (mock mode only):
/// `--dart-define=SIM_SPEED_MPS=20`. Defaults to ~50 km/h city driving.
const String _simSpeedEnv = String.fromEnvironment('SIM_SPEED_MPS');
final double _defaultSimSpeedMps = double.tryParse(_simSpeedEnv) ?? 14;
double _simSpeedMps = _defaultSimSpeedMps;

/// Drive along [path] (road geometry) at [speedMps] (default: SIM_SPEED_MPS or
/// ~50 km/h). Replaces any current path.
void driveSimulatedPath(
  List<({double lat, double lng})> path, {
  double? speedMps,
}) {
  if (_mockPoint == null || path.length < 2) return;
  _simPath = path;
  _simIdx = 0;
  _simSpeedMps = speedMps ?? _defaultSimSpeedMps;
  _simCurrent = path.first;
}

/// Metres between two coordinates (haversine).
double _distM(({double lat, double lng}) a, ({double lat, double lng}) b) {
  const r = 6371000.0;
  final dLat = (b.lat - a.lat) * pi / 180;
  final dLng = (b.lng - a.lng) * pi / 180;
  final la1 = a.lat * pi / 180;
  final la2 = b.lat * pi / 180;
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(la1) * cos(la2) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * r * asin(min(1.0, sqrt(h)));
}

/// True once the car has reached the end of its route.
bool get simulatedArrived =>
    _simPath.length >= 2 && _simIdx >= _simPath.length - 1;

/// The part of the route NOT yet driven, starting at the car's exact current
/// position. The map draws this so the line shrinks behind the car, like Uber.
/// Empty once the destination is reached (line disappears on arrival).
List<({double lat, double lng})> simulatedRemainingPath() {
  if (_simPath.length < 2 || _simCurrent == null) return const [];
  if (_simIdx >= _simPath.length - 1) return const [];
  return [_simCurrent!, ..._simPath.sublist(_simIdx + 1)];
}

({double lat, double lng}) _advanceSim() {
  var cur = _simCurrent!;
  if (_simPath.length < 2 || _simIdx >= _simPath.length - 1) return cur;
  // Distance to cover this tick.
  var budget = _simSpeedMps * (_tickMs / 1000.0);
  final from = cur;
  while (budget > 0 && _simIdx < _simPath.length - 1) {
    final next = _simPath[_simIdx + 1];
    final segLeft = _distM(cur, next);
    if (segLeft <= budget) {
      budget -= segLeft;
      cur = next;
      _simIdx++;
    } else {
      final f = budget / segLeft;
      cur = (
        lat: cur.lat + (next.lat - cur.lat) * f,
        lng: cur.lng + (next.lng - cur.lng) * f,
      );
      budget = 0;
    }
  }
  if (cur.lat != from.lat || cur.lng != from.lng) {
    _simHeading =
        ((atan2(cur.lng - from.lng, cur.lat - from.lat) * 180 / pi) + 360) % 360;
  }
  _simCurrent = cur;
  return cur;
}

Stream<Position> driverPositionStream() {
  final mock = _mockPoint;
  if (mock != null) {
    // Ticks fast so the car glides; when there's no active target it simply
    // re-broadcasts the same point to keep presence fresh in the geo index.
    return Stream<Position>.multi((controller) {
      _simCurrent ??= (lat: mock.lat, lng: mock.lng);
      controller.add(
        _mockPositionAt(_simCurrent!.lat, _simCurrent!.lng, heading: _simHeading),
      );
      final timer = Timer.periodic(
        const Duration(milliseconds: _tickMs),
        (_) {
          final p = _advanceSim();
          controller.add(_mockPositionAt(p.lat, p.lng, heading: _simHeading));
        },
      );
      controller.onCancel = timer.cancel;
    });
  }
  return Geolocator.getPositionStream(
    locationSettings: _platformLocationSettings(),
  );
}

/// Real-GPS settings. On Android we run a **foreground service** so the OS keeps
/// feeding location while the driver app is backgrounded (navigating, screen
/// off) — without it Android throttles/stops updates and the rider's map freezes
/// mid-ride. Elsewhere a plain high-accuracy stream is enough.
LocationSettings _platformLocationSettings() {
  if (Platform.isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
      forceLocationManager: false,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: '${AppBrand.name} Driver — online',
        notificationText: 'Sharing your location so riders can track the ride.',
        enableWakeLock: true,
        setOngoing: true,
        // The Road-V as a white silhouette (res/drawable/ic_stat_ridevela.xml).
        // The default, the colour launcher icon, shows as a grey blob.
        notificationIcon:
            AndroidResource(name: 'ic_stat_ridevela', defType: 'drawable'),
      ),
    );
  }
  if (Platform.isIOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
      // Keeps iOS delivering updates in the background (paired with the
      // UIBackgroundModes:location entitlement in Info.plist).
      allowBackgroundLocationUpdates: true,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );
  }
  return const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );
}
