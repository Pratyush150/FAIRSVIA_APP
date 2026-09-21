import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rider_app/features/trip/location_service.dart';
import 'package:shared_models/shared_models.dart';

/// Scripted Geolocator: every platform answer is a field the test sets.
class FakeGateway implements LocationGateway {
  bool servicesOn = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;
  LocationAccuracyStatus afterFullAccuracyRequest =
      LocationAccuracyStatus.precise;
  Object? positionError;
  int requestPermissionCalls = 0;
  int fullAccuracyCalls = 0;
  String? purposeKey;

  @override
  Future<bool> isLocationServiceEnabled() async => servicesOn;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls++;
    return afterRequest;
  }

  @override
  Future<Position> getCurrentPosition() async {
    if (positionError != null) throw positionError!;
    return Position(
      latitude: 25.7760,
      longitude: -80.1880,
      timestamp: DateTime(2026),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async => accuracy;
  @override
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({
    required String purposeKey,
  }) async {
    fullAccuracyCalls++;
    this.purposeKey = purposeKey;
    accuracy = afterFullAccuracyRequest;
    return afterFullAccuracyRequest;
  }
}

void main() {
  late FakeGateway gw;

  LocationService service({
    TargetPlatform platform = TargetPlatform.android,
    bool releaseMode = false,
    String mockLocation = '',
  }) => LocationService(
    gateway: gw,
    platformOverride: platform,
    releaseMode: releaseMode,
    mockLocation: mockLocation,
  );

  setUp(() => gw = FakeGateway());

  test('a granted permission yields a real GPS fix', () async {
    final r = await service().resolve();
    expect(r.source, LocationSource.gps);
    expect(r.isReal, isTrue);
    expect(r.issue, isNull);
    expect(r.point, const GeoPoint(25.7760, -80.1880));
    expect(r.reducedAccuracy, isFalse);
  });

  test('location services off → fallback point, flagged servicesOff', () async {
    gw.servicesOn = false;
    final r = await service().resolve();
    expect(r.source, LocationSource.fallback);
    expect(r.isReal, isFalse);
    expect(r.issue, LocationIssue.servicesOff);
    expect(r.point, LocationService.fallback);
    expect(gw.requestPermissionCalls, 0);
  });

  test('denied → prompts once; still denied → flagged denied', () async {
    gw.permission = LocationPermission.denied;
    gw.afterRequest = LocationPermission.denied;
    final r = await service().resolve();
    expect(gw.requestPermissionCalls, 1);
    expect(r.issue, LocationIssue.denied);
    expect(r.source, LocationSource.fallback);
  });

  test('denied → granted on prompt → GPS', () async {
    gw.permission = LocationPermission.denied;
    gw.afterRequest = LocationPermission.whileInUse;
    final r = await service().resolve();
    expect(r.source, LocationSource.gps);
  });

  test(
    'deniedForever is reported distinctly (Settings, not a re-prompt)',
    () async {
      gw.permission = LocationPermission.deniedForever;
      final r = await service().resolve();
      expect(gw.requestPermissionCalls, 0);
      expect(r.issue, LocationIssue.deniedForever);
    },
  );

  test('a platform error reads as error, never a silent fallback', () async {
    gw.positionError = StateError('no fix');
    final r = await service().resolve();
    expect(r.source, LocationSource.fallback);
    expect(r.issue, LocationIssue.error);
  });

  group('iOS precise location', () {
    test(
      'reduced → asks for temporary full accuracy once with PreciseRide',
      () async {
        gw.accuracy = LocationAccuracyStatus.reduced;
        gw.afterFullAccuracyRequest = LocationAccuracyStatus.precise;
        final s = service(platform: TargetPlatform.iOS);
        final r = await s.resolve();
        expect(gw.fullAccuracyCalls, 1);
        expect(gw.purposeKey, 'PreciseRide');
        expect(r.source, LocationSource.gps);
        expect(r.reducedAccuracy, isFalse);
      },
    );

    test(
      'still reduced after the prompt → reducedAccuracy, prompt not repeated',
      () async {
        gw.accuracy = LocationAccuracyStatus.reduced;
        gw.afterFullAccuracyRequest = LocationAccuracyStatus.reduced;
        final s = service(platform: TargetPlatform.iOS);
        final first = await s.resolve();
        expect(first.reducedAccuracy, isTrue);
        expect(first.source, LocationSource.gps);
        final second = await s.resolve();
        expect(second.reducedAccuracy, isTrue);
        expect(gw.fullAccuracyCalls, 1, reason: 'asked once per session');
      },
    );

    test('precise → no prompt', () async {
      final r = await service(platform: TargetPlatform.iOS).resolve();
      expect(gw.fullAccuracyCalls, 0);
      expect(r.reducedAccuracy, isFalse);
    });

    test('Android never consults the accuracy API', () async {
      gw.accuracy = LocationAccuracyStatus.reduced;
      final r = await service(platform: TargetPlatform.android).resolve();
      expect(gw.fullAccuracyCalls, 0);
      expect(r.reducedAccuracy, isFalse);
    });
  });

  group('MOCK_LOCATION', () {
    test('debug builds use the mock without touching the platform', () async {
      gw.servicesOn = false; // would fail if consulted
      final s = service(mockLocation: '18.4932,73.7153');
      expect(s.usingMock, isTrue);
      final r = await s.resolve();
      expect(r.source, LocationSource.mock);
      expect(r.isReal, isTrue);
      expect(r.point, const GeoPoint(18.4932, 73.7153));
    });

    test('release builds ignore the mock and read real GPS', () async {
      final s = service(mockLocation: '18.4932,73.7153', releaseMode: true);
      expect(s.usingMock, isFalse);
      final r = await s.resolve();
      expect(r.source, LocationSource.gps);
      expect(r.point, const GeoPoint(25.7760, -80.1880));
    });

    test('a malformed mock is ignored', () async {
      final r = await service(mockLocation: 'nonsense').resolve();
      expect(r.source, LocationSource.gps);
    });
  });
}
