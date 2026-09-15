import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

/// Where a resolved location came from. Only [gps] and [mock] are real
/// positions; [fallback] is a city centre and must never be used as a pickup
/// without the rider explicitly choosing one.
enum LocationSource { gps, mock, fallback }

/// Why a real position could not be read.
enum LocationIssue { servicesOff, denied, deniedForever, error }

/// The outcome of [LocationService.resolve].
@immutable
class LocationResult {
  const LocationResult({
    required this.point,
    required this.source,
    this.issue,
    this.reducedAccuracy = false,
  });

  final GeoPoint point;
  final LocationSource source;

  /// Set when [source] is [LocationSource.fallback].
  final LocationIssue? issue;

  /// iOS "Precise Location" is off (approximate ~1-5 km fix). The position is
  /// real but not good enough to set a pickup automatically.
  final bool reducedAccuracy;

  /// True when [point] is a real fix (GPS or dev mock), not the city fallback.
  bool get isReal => source != LocationSource.fallback;

  @override
  bool operator ==(Object other) =>
      other is LocationResult &&
      other.point == point &&
      other.source == source &&
      other.issue == issue &&
      other.reducedAccuracy == reducedAccuracy;

  @override
  int get hashCode => Object.hash(point, source, issue, reducedAccuracy);

  @override
  String toString() =>
      'LocationResult($point, $source, issue: $issue, reduced: $reducedAccuracy)';
}

/// The slice of Geolocator the service needs, as an interface so tests can
/// script permission/services states without platform channels.
abstract class LocationGateway {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> getCurrentPosition();
  Future<LocationAccuracyStatus> getLocationAccuracy();
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({
    required String purposeKey,
  });
}

class _GeolocatorGateway implements LocationGateway {
  const _GeolocatorGateway();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  @override
  Future<Position> getCurrentPosition() => Geolocator.getCurrentPosition();
  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() =>
      Geolocator.getLocationAccuracy();
  @override
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({
    required String purposeKey,
  }) =>
      Geolocator.requestTemporaryFullAccuracy(purposeKey: purposeKey);
}

/// Resolves the rider's current location. Every failure is reported (source
/// + issue) rather than silently swapped for the city-centre fallback, so the
/// UI can show a "Location is off" banner and refuse to use the fallback as a
/// pickup.
class LocationService {
  LocationService({
    LocationGateway? gateway,
    bool releaseMode = kReleaseMode,
    TargetPlatform? platformOverride,
    String mockLocation = _mockLocation,
  })  : _gateway = gateway ?? const _GeolocatorGateway(),
        _releaseMode = releaseMode,
        _platform = platformOverride,
        _mockPoint = releaseMode ? null : _parsePoint(mockLocation);

  final LocationGateway _gateway;
  final bool _releaseMode;
  final TargetPlatform? _platform;
  final GeoPoint? _mockPoint;

  /// The temporary full-accuracy prompt may only be shown once per session;
  /// iOS ignores repeat requests anyway and the sheet would nag.
  bool _askedFullAccuracy = false;

  /// The `NSLocationTemporaryUsageDescriptionDictionary` key in Info.plist.
  static const String preciseRidePurposeKey = 'PreciseRide';

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
  /// Ignored in release builds so a leftover define can't ship a fake pickup.
  static const String _mockLocation = String.fromEnvironment('MOCK_LOCATION');

  /// Whether the dev mock is in effect for this service instance.
  bool get usingMock => !_releaseMode && _mockPoint != null;

  /// True when the app currently holds foreground (or always) location access.
  Future<bool> hasPermission() async {
    if (_mockPoint != null) return true;
    final p = await _gateway.checkPermission();
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  /// Ask for location access. Prompts, and if the user has permanently denied
  /// it, opens the app's system settings so they can enable it. Returns
  /// whether access is granted afterwards.
  Future<bool> requestPermission() async {
    if (_mockPoint != null) return true;
    if (!await _gateway.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    }
    var p = await _gateway.checkPermission();
    if (p == LocationPermission.denied) {
      p = await _gateway.requestPermission();
    }
    if (p == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      p = await _gateway.checkPermission();
    }
    return p == LocationPermission.whileInUse || p == LocationPermission.always;
  }

  /// A live stream of the rider's position (real GPS), for keeping the map on
  /// the phone's actual location and snapping to the first real fix once GPS
  /// resolves. Emits nothing when mocked (the caller keeps its resolved position).
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

  /// The rider's position as a bare point (real fix or the city fallback);
  /// see [resolve] for the source/issue detail.
  Future<GeoPoint> currentOrFallback() async => (await resolve()).point;

  Future<LocationResult> resolve() async {
    final mock = _mockPoint;
    if (mock != null) {
      return LocationResult(point: mock, source: LocationSource.mock);
    }
    try {
      if (!await _gateway.isLocationServiceEnabled()) {
        return _fallback(LocationIssue.servicesOff);
      }

      var permission = await _gateway.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _gateway.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return _fallback(LocationIssue.denied);
        case LocationPermission.deniedForever:
          return _fallback(LocationIssue.deniedForever);
        case LocationPermission.unableToDetermine:
          return _fallback(LocationIssue.error);
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          break;
      }

      final reduced = await _checkPreciseAccuracy();
      final pos = await _gateway.getCurrentPosition();
      return LocationResult(
        point: GeoPoint(pos.latitude, pos.longitude),
        source: LocationSource.gps,
        reducedAccuracy: reduced,
      );
    } catch (_) {
      // A fresh fix can time out indoors; the phone's last known fix is still
      // the rider's real neighbourhood — far better than the city fallback.
      final cached = await _lastKnown();
      if (cached != null) {
        return LocationResult(point: cached, source: LocationSource.gps);
      }
      return _fallback(LocationIssue.error);
    }
  }

  /// iOS 14+ lets the user grant only approximate location. Ask once for
  /// temporary precise access (the purpose string lives in Info.plist under
  /// [preciseRidePurposeKey]); report `true` if it's still reduced so the UI
  /// can point the rider at Settings.
  Future<bool> _checkPreciseAccuracy() async {
    if ((_platform ?? defaultTargetPlatform) != TargetPlatform.iOS) {
      return false;
    }
    var status = await _gateway.getLocationAccuracy();
    if (status != LocationAccuracyStatus.reduced) return false;
    if (!_askedFullAccuracy) {
      _askedFullAccuracy = true;
      status = await _gateway.requestTemporaryFullAccuracy(
        purposeKey: preciseRidePurposeKey,
      );
    }
    return status == LocationAccuracyStatus.reduced;
  }

  LocationResult _fallback(LocationIssue issue) => LocationResult(
        point: fallback,
        source: LocationSource.fallback,
        issue: issue,
      );
}
