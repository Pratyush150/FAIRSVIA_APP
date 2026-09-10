import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:driver_app/features/driver/driver_cubit.dart';
import 'package:driver_app/features/driver/location_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockDriverRemote extends Mock implements DriverRemoteDataSource {}

class MockRatings extends Mock implements RatingsRemoteDataSource {}

/// In-memory RealtimeClient: push server events and capture client emits.
class FakeRealtimeClient implements RealtimeClient {
  final _controllers = <String, StreamController<Map<String, dynamic>>>{};
  final List<(String, Map<String, dynamic>)> emitted = [];
  bool _connected = false;

  /// When set, [connect] fails — models a slow/dead first socket handshake.
  Object? connectError;

  @override
  Future<void> connect(String token) async {
    if (connectError != null) throw connectError!;
    _connected = true;
  }

  @override
  void disconnect() => _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<Map<String, dynamic>> on(String event) => _controllers
      .putIfAbsent(event, () => StreamController<Map<String, dynamic>>.broadcast())
      .stream;

  final _reconnects = StreamController<void>.broadcast();

  @override
  Stream<void> get reconnects => _reconnects.stream;

  final _connection = StreamController<bool>.broadcast();

  @override
  Stream<bool> get connection => _connection.stream;

  @override
  void emit(String event, Map<String, dynamic> data) =>
      emitted.add((event, data));

  void push(String event, Map<String, dynamic> data) =>
      _controllers[event]?.add(data);

  void pushReconnect() => _reconnects.add(null);

  void pushConnection(bool up) => _connection.add(up);
}

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late FakeRealtimeClient realtime;
  late MockDriverRemote remote;
  late MockRatings ratings;

  final offerJson = <String, dynamic>{
    'tripId': 'trip-1',
    'pickup': {'lat': 12.96, 'lng': 77.63, 'address': 'A'},
    'dropoff': {'lat': 12.97, 'lng': 77.59, 'address': 'B'},
    'fare': 142.98,
    'tier': 'economy',
    'distanceM': 6865,
    'durationS': 824,
    'expiresInSec': 15,
  };

  final trip = Trip(
    id: 'trip-1',
    status: TripStatus.accepted,
    tier: 'economy',
    pickup: const TripEndpoint(point: GeoPoint(12.96, 77.63), address: 'A'),
    dropoff: const TripEndpoint(point: GeoPoint(12.97, 77.59), address: 'B'),
  );

  // Location access is granted unless a test says otherwise; the real check
  // talks to the geolocator plugin, which has no host under flutter_test.
  LocationAccess access = LocationAccess.granted;
  DriverCubit make({Duration acceptGrace = const Duration(seconds: 5)}) =>
      DriverCubit(
        realtime,
        remote,
        ratings,
        checkLocation: () async => access,
        acceptGrace: acceptGrace,
      );

  setUp(() {
    access = LocationAccess.granted;
    realtime = FakeRealtimeClient();
    remote = MockDriverRemote();
    ratings = MockRatings();
    when(() => ratings.rate(any(),
        stars: any(named: 'stars'),
        comment: any(named: 'comment'),
        tags: any(named: 'tags'))).thenAnswer((_) async {});
    when(() => remote.setStatus(any())).thenAnswer((_) async {});
    when(() => remote.getActiveTrip()).thenAnswer((_) async => null);
    when(() => remote.getTrip(any())).thenAnswer((_) async => trip);
    when(() => remote.arrived(any())).thenAnswer((_) async {});
    when(() => remote.start(any(), any())).thenAnswer((_) async {});
    when(() => remote.complete(any())).thenAnswer(
      (_) async => <String, dynamic>{
        'fareFinal': 142.98,
        'paymentMode': 'card',
      },
    );
    when(() => remote.earnings(range: any(named: 'range'))).thenAnswer(
      (_) async => const DriverEarnings(total: 142.98, trips: 1, range: 'today'),
    );
  });

  test('drives the full offer → complete lifecycle', () async {
    final cubit = make();
    await cubit.init('token');
    expect(realtime.isConnected, isTrue);

    await cubit.goOnline();
    expect(cubit.state.phase, DriverPhase.online);

    realtime.push('trip:offer', offerJson);
    await tick();
    expect(cubit.state.phase, DriverPhase.offered);
    expect(cubit.state.offer?.tripId, 'trip-1');

    cubit.acceptOffer();
    expect(realtime.emitted.any((e) => e.$1 == 'trip:accept'), isTrue);

    realtime.push('trip:assigned', {'tripId': 'trip-1'});
    await tick();
    expect(cubit.state.phase, DriverPhase.enRoute);
    expect(cubit.state.trip?.id, 'trip-1');

    await cubit.markArrived();
    expect(cubit.state.phase, DriverPhase.arrived);

    await cubit.startTrip('1234');
    expect(cubit.state.phase, DriverPhase.onTrip);
    verify(() => remote.start('trip-1', '1234')).called(1);

    await cubit.completeTrip();
    // Parks in `completed` so the driver can rate the rider first.
    expect(cubit.state.phase, DriverPhase.completed);
    expect(cubit.state.lastEarned, 142.98);
    expect(cubit.state.lastTripId, 'trip-1');

    await cubit.rateRider(5);
    expect(cubit.state.riderRating, 5);
    verify(() => ratings.rate('trip-1', stars: 5)).called(1);

    cubit.dismissCompleted();
    expect(cubit.state.phase, DriverPhase.online);

    await cubit.close();
  });

  test('declining an offer returns to online and emits trip:decline', () async {
    final cubit = make();
    await cubit.init('token');
    await cubit.goOnline();
    realtime.push('trip:offer', offerJson);
    await tick();

    cubit.declineOffer();
    expect(cubit.state.phase, DriverPhase.online);
    expect(cubit.state.offer, isNull);
    expect(realtime.emitted.any((e) => e.$1 == 'trip:decline'), isTrue);

    await cubit.close();
  });

  test('reconnect re-announces presence and re-syncs the active trip', () async {
    final cubit = make();
    await cubit.init('token');
    await cubit.goOnline();
    realtime.push('trip:assigned', {'tripId': 'trip-1'});
    await tick();
    expect(cubit.state.phase, DriverPhase.enRoute);

    // Rider cancelled while the socket was down; the resync should catch it.
    final cancelled = Trip(
      id: 'trip-1',
      status: TripStatus.cancelled,
      tier: 'economy',
      pickup: const TripEndpoint(point: GeoPoint(12.96, 77.63), address: 'A'),
      dropoff: const TripEndpoint(point: GeoPoint(12.97, 77.59), address: 'B'),
    );
    when(() => remote.getTrip('trip-1')).thenAnswer((_) async => cancelled);

    realtime.pushReconnect();
    await tick();

    expect(cubit.state.phase, DriverPhase.online);
    expect(cubit.state.trip, isNull);
    expect(
      realtime.emitted.where((e) => e.$1 == 'driver:status').length,
      greaterThanOrEqualTo(2), // initial goOnline + reconnect re-announce
    );

    await cubit.close();
  });

  test('init restores an active trip after a cold restart', () async {
    // Backend reports a live accepted trip for a freshly-launched app.
    when(() => remote.getActiveTrip()).thenAnswer((_) async => trip);

    final cubit = make();
    await cubit.init('token');
    await tick();

    // Restored straight into the en-route phase with the trip, and re-announced
    // presence — no idle "go online" home while a ride is in flight.
    expect(cubit.state.phase, DriverPhase.enRoute);
    expect(cubit.state.trip?.id, 'trip-1');
    expect(cubit.state.isOnline, isTrue);
    expect(realtime.emitted.any((e) => e.$1 == 'driver:status'), isTrue);

    await cubit.close();
  });

  test('init with an in-progress trip restores the on-trip phase', () async {
    final onTrip = Trip(
      id: 'trip-1',
      status: TripStatus.inProgress,
      tier: 'economy',
      pickup: const TripEndpoint(point: GeoPoint(12.96, 77.63), address: 'A'),
      dropoff: const TripEndpoint(point: GeoPoint(12.97, 77.59), address: 'B'),
    );
    when(() => remote.getActiveTrip()).thenAnswer((_) async => onTrip);

    final cubit = make();
    await cubit.init('token');
    await tick();

    expect(cubit.state.phase, DriverPhase.onTrip);
    expect(cubit.state.trip?.id, 'trip-1');

    await cubit.close();
  });

  test('rider cancellation after assignment resets the driver', () async {
    final cubit = make();
    await cubit.init('token');
    await cubit.goOnline();
    realtime.push('trip:assigned', {'tripId': 'trip-1'});
    await tick();
    expect(cubit.state.phase, DriverPhase.enRoute);

    realtime.push('trip:cancelled', {'by': 'rider'});
    await tick();
    expect(cubit.state.phase, DriverPhase.online);
    expect(cubit.state.trip, isNull);

    await cubit.close();
  });

  test('onboard() never re-emits needsOnboarding=true (double-dialog bug)',
      () async {
    // First goOnline is rejected until onboarding completes.
    when(() => remote.setStatus('online')).thenThrow(
        const ApiException('Complete driver onboarding first',
            statusCode: 403));
    final cubit = make();
    await cubit.init('token');
    await cubit.goOnline();
    expect(cubit.state.needsOnboarding, isTrue);

    // Now onboarding succeeds and going online works.
    when(() => remote.setStatus('online')).thenAnswer((_) async {});
    when(() => remote.onboarding(
          vehicleMake: any(named: 'vehicleMake'),
          vehicleModel: any(named: 'vehicleModel'),
          plateNumber: any(named: 'plateNumber'),
          vehicleTier: any(named: 'vehicleTier'),
          vehicleColor: any(named: 'vehicleColor'),
        )).thenAnswer((_) async {});

    // Every state emitted during onboard() must already have the flag
    // cleared — an interim needsOnboarding=true emission is what used to
    // stack a second "Set up your vehicle" dialog on the home page.
    final sawStaleFlag = <bool>[];
    final sub = cubit.stream.listen(
        (s) => sawStaleFlag.add(s.needsOnboarding));
    await cubit.onboard(
        make: 'Toyota', model: 'Camry', plate: 'FLA 1234', tier: 'economy');
    await sub.cancel();

    expect(sawStaleFlag, isNotEmpty);
    expect(sawStaleFlag.any((v) => v), isFalse);
    expect(cubit.state.phase, DriverPhase.online);

    await cubit.close();
  });

  test('socket up/down edges drive the connection banner state', () async {
    final cubit = make();
    await cubit.init('token');
    expect(cubit.state.connected, isTrue); // optimistic default

    realtime.pushConnection(false);
    await tick();
    expect(cubit.state.connected, isFalse);

    realtime.pushConnection(true);
    await tick();
    expect(cubit.state.connected, isTrue);

    await cubit.close();
  });

  // ── #1 Accept that never resolves ─────────────────────────────────────────
  group('accepted offer that never assigns', () {
    // expiresInSec 0 + zero grace so the safety timer fires immediately.
    final instantOffer = <String, dynamic>{...offerJson, 'expiresInSec': 0};

    blocTest<DriverCubit, DriverState>(
      'safety timer resets to online with a visible error when neither '
      'trip:assigned nor trip:offer_expired arrives',
      build: () => make(acceptGrace: Duration.zero),
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
        realtime.push('trip:offer', instantOffer);
        await tick();
        cubit.acceptOffer();
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        // goOnline
        isA<DriverState>().having((s) => s.busy, 'busy', isTrue),
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.online)
            .having((s) => s.busy, 'busy', isFalse),
        // offer shown
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.offered)
            .having((s) => s.offer?.tripId, 'offer', 'trip-1'),
        // accept → spinner
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.offered)
            .having((s) => s.busy, 'busy', isTrue),
        // timer → back online, card gone, error surfaced
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.online)
            .having((s) => s.offer, 'offer', isNull)
            .having((s) => s.busy, 'busy', isFalse)
            .having((s) => s.error, 'error',
                'That ride was taken or cancelled'),
      ],
      verify: (cubit) {
        expect(realtime.emitted.any((e) => e.$1 == 'trip:accept'), isTrue);
      },
    );

    test('a new offer is accepted again after the timer reset', () async {
      final cubit = make(acceptGrace: Duration.zero);
      await cubit.init('token');
      await cubit.goOnline();
      realtime.push('trip:offer', instantOffer);
      await tick();
      cubit.acceptOffer();
      await tick();
      expect(cubit.state.phase, DriverPhase.online);

      // Previously phase stayed `offered`, so _onOffer dropped this forever.
      realtime.push('trip:offer', {...offerJson, 'tripId': 'trip-2'});
      await tick();
      expect(cubit.state.phase, DriverPhase.offered);
      expect(cubit.state.offer?.tripId, 'trip-2');
      await cubit.close();
    });

    test('trip:assigned before the timer cancels it (no spurious reset)',
        () async {
      final cubit = make(acceptGrace: Duration.zero);
      await cubit.init('token');
      await cubit.goOnline();
      realtime.push('trip:offer', instantOffer);
      await tick();
      cubit.acceptOffer();
      realtime.push('trip:assigned', {'tripId': 'trip-1'});
      await tick();
      await tick();
      expect(cubit.state.phase, DriverPhase.enRoute);
      expect(cubit.state.error, isNull);
      await cubit.close();
    });

    test('trip:offer_expired while Accept is pending clears the card',
        () async {
      final cubit = make();
      await cubit.init('token');
      await cubit.goOnline();
      realtime.push('trip:offer', offerJson);
      await tick();
      cubit.acceptOffer();
      expect(cubit.state.busy, isTrue);

      // Backend: accepted but assign() failed (rider cancelled mid-window).
      realtime.push('trip:offer_expired', {'tripId': 'trip-1'});
      await tick();
      expect(cubit.state.phase, DriverPhase.online);
      expect(cubit.state.offer, isNull);
      expect(cubit.state.busy, isFalse);
      expect(cubit.state.error, 'That ride was taken or cancelled');
      await cubit.close();
    });

    test('a stale trip:offer_expired for another trip leaves the card alone',
        () async {
      final cubit = make();
      await cubit.init('token');
      await cubit.goOnline();
      realtime.push('trip:offer', offerJson);
      await tick();

      realtime.push('trip:offer_expired', {'tripId': 'trip-OLD'});
      await tick();
      expect(cubit.state.phase, DriverPhase.offered);
      expect(cubit.state.offer?.tripId, 'trip-1');
      await cubit.close();
    });
  });

  // ── #3 Location gate before going online ──────────────────────────────────
  group('goOnline location gate', () {
    blocTest<DriverCubit, DriverState>(
      'stays offline with a settings-actionable error when permission is '
      'permanently denied — never calls setStatus(online)',
      build: () => make(),
      setUp: () => access = LocationAccess.deniedForever,
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
      },
      expect: () => [
        isA<DriverState>()
            .having((s) => s.busy, 'busy', isTrue)
            .having((s) => s.locationIssue, 'locationIssue', isNull),
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.offline)
            .having((s) => s.busy, 'busy', isFalse)
            .having((s) => s.locationIssue, 'locationIssue',
                LocationAccess.deniedForever)
            .having((s) => s.error, 'error', contains('Settings')),
      ],
      verify: (_) {
        verifyNever(() => remote.setStatus('online'));
        expect(realtime.emitted.any((e) => e.$1 == 'driver:status'), isFalse);
      },
    );

    test('services off → servicesOff issue, still offline', () async {
      access = LocationAccess.servicesOff;
      final cubit = make();
      await cubit.init('token');
      await cubit.goOnline();
      expect(cubit.state.phase, DriverPhase.offline);
      expect(cubit.state.locationIssue, LocationAccess.servicesOff);
      verifyNever(() => remote.setStatus('online'));
      await cubit.close();
    });

    test('granted on a retry clears the issue and goes online', () async {
      access = LocationAccess.denied;
      final cubit = make();
      await cubit.init('token');
      await cubit.goOnline();
      expect(cubit.state.phase, DriverPhase.offline);
      expect(cubit.state.locationIssue, LocationAccess.denied);

      access = LocationAccess.granted;
      await cubit.goOnline();
      expect(cubit.state.phase, DriverPhase.online);
      expect(cubit.state.locationIssue, isNull);
      expect(cubit.state.error, isNull);
      verify(() => remote.setStatus('online')).called(1);
      await cubit.close();
    });
  });

  // ── #6 Listeners registered before connect ────────────────────────────────
  test('a failed first connect still leaves every socket listener wired',
      () async {
    realtime.connectError = TimeoutException('handshake');
    final cubit = make();
    await expectLater(cubit.init('token'), throwsA(isA<TimeoutException>()));

    // The connection-edge listener must already be live…
    realtime.pushConnection(false);
    await tick();
    expect(cubit.state.connected, isFalse);
    realtime.pushConnection(true);
    await tick();
    expect(cubit.state.connected, isTrue);

    // …and so must trip events, once the socket layer recovers on its own.
    await cubit.goOnline();
    realtime.push('trip:offer', offerJson);
    await tick();
    expect(cubit.state.phase, DriverPhase.offered);

    await cubit.close();
  });
}
