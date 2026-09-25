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
  Future<void> connectWith(AccessTokenProvider tokenProvider) async =>
      connect((await tokenProvider()) ?? '');

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

/// States `init()` emits on its own with the default stubs: one for today's
/// earnings (`lastEarned`). blocTests that start with `init` skip these.
const initStates = 1;

void main() {
  late FakeRealtimeClient realtime;
  late MockDriverRemote remote;
  late MockRatings ratings;

  final offerJson = <String, dynamic>{
    'rider': {'name': 'Ava Rider', 'rating': 4.9},
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

  test('resumeFromBackground rebuilds the socket even when it looks connected',
      () async {
    final cubit = make();
    await cubit.init('token');
    await cubit.goOnline();
    realtime.emitted.clear();
    // The fake reports connected; a real client would too after a suspend.
    expect(realtime.isConnected, isTrue);
    await cubit.resumeFromBackground('token');
    // A fresh connect re-announces presence (`_onReconnect`).
    expect(
      realtime.emitted.where((e) => e.$1 == 'driver:status').length,
      greaterThanOrEqualTo(1),
    );
    expect(cubit.state.connected, isTrue);
    await cubit.close();
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
    // Rider name is carried over from the offer for the chat header.
    expect(cubit.state.riderName, 'Ava Rider');

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

  test('rider ends the trip early: trip:completed moves the driver to the '
      'trip-complete sheet with the adjusted fare', () async {
    final cubit = make();
    await cubit.init('token');
    await cubit.goOnline();
    realtime.push('trip:offer', offerJson);
    await tick();
    cubit.acceptOffer();
    realtime.push('trip:assigned', {'tripId': 'trip-1'});
    await tick();
    await cubit.markArrived();
    await cubit.startTrip('1234');
    expect(cubit.state.phase, DriverPhase.onTrip);

    // A stray event for another trip is ignored.
    realtime.push('trip:completed', {'tripId': 'other', 'fareFinal': 1});
    await tick();
    expect(cubit.state.phase, DriverPhase.onTrip);

    realtime.push('trip:completed', {
      'tripId': 'trip-1',
      'fareFinal': 75,
      'paymentMode': 'cash',
      'breakdown': {
        'fareBasis': 'minimum',
        'endedEarly': true,
        'endReason': 'Rider ended the trip',
      },
    });
    await tick();
    expect(cubit.state.phase, DriverPhase.completed);
    expect(cubit.state.lastTripId, 'trip-1');
    expect(cubit.state.cashToCollect, 75);
    expect(cubit.state.endNote, 'The rider ended the trip here · minimum fare');
    verifyNever(() => remote.complete(any()));
    await cubit.close();
  });

  group('offers on the trip-complete sheet (back-to-back rides)', () {
    Future<DriverCubit> completed() async {
      final cubit = make();
      await cubit.init('token');
      await cubit.goOnline();
      realtime.push('trip:offer', offerJson);
      await tick();
      cubit.acceptOffer();
      realtime.push('trip:assigned', {'tripId': 'trip-1'});
      await tick();
      await cubit.markArrived();
      await cubit.startTrip('1234');
      await cubit.completeTrip();
      expect(cubit.state.phase, DriverPhase.completed);
      return cubit;
    }

    final nextOffer = <String, dynamic>{...offerJson, 'tripId': 'trip-2'};

    test('an offer on the completion sheet is shown, not dropped', () async {
      final cubit = await completed();
      realtime.push('trip:offer', nextOffer);
      await tick();
      expect(cubit.state.phase, DriverPhase.offered);
      expect(cubit.state.offer?.tripId, 'trip-2');
      // The completion sheet is still underneath the card.
      expect(cubit.state.lastTripId, 'trip-1');
      await cubit.close();
    });

    test('location keeps streaming on the completion sheet', () async {
      final cubit = await completed();
      realtime.emitted.clear();
      cubit.sendLocation(12.97, 77.59);
      expect(realtime.emitted.any((e) => e.$1 == 'driver:location'), isTrue);
      await cubit.close();
    });

    test('accepting closes the completion sheet and starts the new trip; the '
        'unrated rider is skipped', () async {
      final cubit = await completed();
      final trip2 = Trip(
        id: 'trip-2',
        status: TripStatus.accepted,
        tier: 'economy',
        pickup: const TripEndpoint(point: GeoPoint(12.96, 77.63), address: 'C'),
        dropoff: const TripEndpoint(point: GeoPoint(12.97, 77.59), address: 'D'),
      );
      when(() => remote.getTrip('trip-2')).thenAnswer((_) async => trip2);
      realtime.push('trip:offer', nextOffer);
      await tick();
      cubit.acceptOffer();
      expect(
        realtime.emitted.any(
            (e) => e.$1 == 'trip:accept' && e.$2['tripId'] == 'trip-2'),
        isTrue,
      );
      realtime.push('trip:assigned', {'tripId': 'trip-2'});
      await tick();
      expect(cubit.state.phase, DriverPhase.enRoute);
      expect(cubit.state.trip?.id, 'trip-2');
      expect(cubit.state.lastTripId, isNull);
      expect(cubit.state.cashToCollect, isNull);
      verifyNever(() => ratings.rate(any(), stars: any(named: 'stars')));
      await cubit.close();
    });

    test('declining returns to the completion sheet so the driver can still '
        'rate', () async {
      final cubit = await completed();
      realtime.push('trip:offer', nextOffer);
      await tick();
      cubit.declineOffer();
      expect(cubit.state.phase, DriverPhase.completed);
      expect(cubit.state.lastTripId, 'trip-1');
      await cubit.rateRider(4);
      verify(() => ratings.rate('trip-1', stars: 4)).called(1);
      await cubit.close();
    });

    test('an expired offer returns to the completion sheet', () async {
      final cubit = await completed();
      realtime.push('trip:offer', nextOffer);
      await tick();
      realtime.push('trip:offer_expired', {'tripId': 'trip-2'});
      await tick();
      expect(cubit.state.phase, DriverPhase.completed);
      await cubit.close();
    });
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
      skip: initStates,
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
      skip: initStates,
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

    blocTest<DriverCubit, DriverState>(
      'stays offline with a Settings error when Precise Location is off '
      '(reduced accuracy) — never calls setStatus(online)',
      build: () => make(),
      setUp: () => access = LocationAccess.reduced,
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
      },
      skip: initStates,
      expect: () => [
        isA<DriverState>()
            .having((s) => s.busy, 'busy', isTrue)
            .having((s) => s.locationIssue, 'locationIssue', isNull),
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.offline)
            .having((s) => s.busy, 'busy', isFalse)
            .having((s) => s.locationIssue, 'locationIssue',
                LocationAccess.reduced)
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

    test('setLocationIssue records a priming refusal and clears on granted',
        () async {
      final cubit = make();
      await cubit.init('token');
      cubit.setLocationIssue(LocationAccess.deniedForever);
      expect(cubit.state.locationIssue, LocationAccess.deniedForever);
      expect(cubit.state.phase, DriverPhase.offline);
      // No snackbar text: the sheet's banner carries the message.
      expect(cubit.state.error, isNull);

      cubit.setLocationIssue(LocationAccess.granted);
      expect(cubit.state.locationIssue, isNull);
      await cubit.close();
    });
  });

  // ── Server-driven presence: driver:status_changed ─────────────────────────
  group('driver:status_changed', () {
    const staleMsg = 'You were set offline — no location received for a '
        'while. Go online again.';
    const dropMsg = "Connection dropped — you're offline. Go online again.";

    blocTest<DriverCubit, DriverState>(
      'offline/stale_location while idle-online flips the UI offline with the '
      'no-location message and tells the server',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
        realtime.emitted.clear();
        realtime.push('driver:status_changed',
            {'status': 'offline', 'reason': 'stale_location'});
        await tick();
      },
      skip: initStates + 2, // goOnline busy → online
      expect: () => [
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.offline)
            .having((s) => s.error, 'error', staleMsg)
            .having((s) => s.busy, 'busy', isFalse),
      ],
      verify: (_) {
        expect(
          realtime.emitted.any((e) =>
              e.$1 == 'driver:status' && e.$2['status'] == 'offline'),
          isTrue,
        );
      },
    );

    blocTest<DriverCubit, DriverState>(
      'offline/presence_lost uses the no-location message',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
        realtime.push('driver:status_changed',
            {'status': 'offline', 'reason': 'presence_lost'});
        await tick();
      },
      skip: initStates + 2,
      expect: () => [
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.offline)
            .having((s) => s.error, 'error', staleMsg),
      ],
    );

    blocTest<DriverCubit, DriverState>(
      'offline/disconnect uses the connection-dropped message and clears an '
      'offer on screen (accept timer included)',
      build: () => make(acceptGrace: Duration.zero),
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
        realtime.push('trip:offer', {...offerJson, 'expiresInSec': 0});
        await tick();
        cubit.acceptOffer();
        realtime.push(
            'driver:status_changed', {'status': 'offline', 'reason': 'disconnect'});
        await tick();
      },
      wait: const Duration(milliseconds: 50),
      skip: initStates + 4, // busy, online, offered, accept-busy
      expect: () => [
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.offline)
            .having((s) => s.offer, 'offer', isNull)
            .having((s) => s.busy, 'busy', isFalse)
            .having((s) => s.error, 'error', dropMsg),
        // No later "taken or cancelled" reset: the accept timer was cancelled.
      ],
    );

    blocTest<DriverCubit, DriverState>(
      'offline/sync while online is the connect-time snapshot our reconnect '
      're-announce supersedes — no flip',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
        realtime.push(
            'driver:status_changed', {'status': 'offline', 'reason': 'sync'});
        await tick();
      },
      skip: initStates + 2,
      expect: () => <DriverState>[],
      verify: (cubit) => expect(cubit.state.phase, DriverPhase.online),
    );

    blocTest<DriverCubit, DriverState>(
      'offline while on a trip is ignored (server never forces mid-trip)',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
        realtime.push('trip:assigned', {'tripId': 'trip-1'});
        await tick();
        realtime.push('driver:status_changed',
            {'status': 'offline', 'reason': 'disconnect'});
        await tick();
      },
      skip: initStates + 3, // busy, online, enRoute
      expect: () => <DriverState>[],
      verify: (cubit) {
        expect(cubit.state.phase, DriverPhase.enRoute);
        expect(cubit.state.error, isNull);
      },
    );

    blocTest<DriverCubit, DriverState>(
      'offline while already offline does nothing',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        realtime.push('driver:status_changed',
            {'status': 'offline', 'reason': 'disconnect'});
        await tick();
      },
      skip: initStates,
      expect: () => <DriverState>[],
    );

    blocTest<DriverCubit, DriverState>(
      'online/sync matching an online app does nothing',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
        realtime.push(
            'driver:status_changed', {'status': 'online', 'reason': 'sync'});
        await tick();
      },
      skip: initStates + 2,
      expect: () => <DriverState>[],
    );

    blocTest<DriverCubit, DriverState>(
      'on_trip/sync matching an in-trip app does nothing',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
        realtime.push('trip:assigned', {'tripId': 'trip-1'});
        await tick();
        realtime.push(
            'driver:status_changed', {'status': 'on_trip', 'reason': 'sync'});
        await tick();
      },
      skip: initStates + 3,
      expect: () => <DriverState>[],
      verify: (_) => verify(() => remote.getActiveTrip()).called(1), // init only
    );

    blocTest<DriverCubit, DriverState>(
      'online/sync while the app is offline restores the online phase (server '
      'still holds our presence from before a relaunch)',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        realtime.push(
            'driver:status_changed', {'status': 'online', 'reason': 'sync'});
        await tick();
      },
      skip: initStates,
      expect: () => [
        isA<DriverState>().having((s) => s.phase, 'phase', DriverPhase.online),
      ],
      verify: (_) => verifyNever(() => remote.setStatus(any())),
    );

    blocTest<DriverCubit, DriverState>(
      'on_trip/sync while the app is offline restores the live trip screen',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        // The trip appears on the server after init's own restore ran.
        when(() => remote.getActiveTrip()).thenAnswer((_) async => trip);
        realtime.push(
            'driver:status_changed', {'status': 'on_trip', 'reason': 'sync'});
        await tick();
      },
      skip: initStates,
      expect: () => [
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.enRoute)
            .having((s) => s.trip?.id, 'trip', 'trip-1'),
      ],
    );

    test('online/on_trip with a non-sync reason never flips an offline app',
        () async {
      final cubit = make();
      await cubit.init('token');
      realtime.push('driver:status_changed',
          {'status': 'online', 'reason': 'presence_lost'});
      realtime.push('driver:status_changed',
          {'status': 'on_trip', 'reason': 'disconnect'});
      await tick();
      expect(cubit.state.phase, DriverPhase.offline);
      await cubit.close();
    });
  });

  // ── Server exception frames ───────────────────────────────────────────────
  group('exception frames', () {
    blocTest<DriverCubit, DriverState>(
      'surface the server message as the cubit error',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        realtime.push('exception', {
          'status': 'error',
          'code': 400,
          'message': 'Finish your current trip before going offline.',
          'event': 'driver:status',
        });
        await tick();
      },
      skip: initStates,
      expect: () => [
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.offline)
            .having((s) => s.error, 'error',
                'Finish your current trip before going offline.'),
      ],
    );

    blocTest<DriverCubit, DriverState>(
      'a refused driver:status while idle-online flips the app offline '
      '(the server never registered us)',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
        realtime.push('exception', {
          'status': 'error',
          'code': 403,
          'message': 'Documents are not verified yet',
          'event': 'driver:status',
        });
        await tick();
      },
      skip: initStates + 2,
      expect: () => [
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.offline)
            .having((s) => s.error, 'error', 'Documents are not verified yet'),
      ],
    );

    blocTest<DriverCubit, DriverState>(
      'a refused frame on another event keeps the phase and shows the message',
      build: () => make(),
      act: (cubit) async {
        await cubit.init('token');
        await cubit.goOnline();
        realtime.push('exception', {
          'status': 'error',
          'code': 400,
          'message': 'tripId must be a UUID',
          'event': 'trip:accept',
        });
        await tick();
      },
      skip: initStates + 2,
      expect: () => [
        isA<DriverState>()
            .having((s) => s.phase, 'phase', DriverPhase.online)
            .having((s) => s.error, 'error', 'tripId must be a UUID'),
      ],
    );

    test('a frame without a message is ignored', () async {
      final cubit = make();
      await cubit.init('token');
      realtime.push('exception', {'status': 'error', 'code': 500});
      await tick();
      expect(cubit.state.error, isNull);
      await cubit.close();
    });
  });

  // ── Arrival geofence ──────────────────────────────────────────────────────
  test('markArrived surfaces the geofence 400 and stays en route', () async {
    when(() => remote.arrived(any())).thenThrow(const ApiException(
        "You're still 340 m from the pickup",
        statusCode: 400));
    final cubit = make();
    await cubit.init('token');
    await cubit.goOnline();
    realtime.push('trip:assigned', {'tripId': 'trip-1'});
    await tick();

    await cubit.markArrived();
    expect(cubit.state.phase, DriverPhase.enRoute);
    expect(cubit.state.busy, isFalse);
    expect(cubit.state.error, "You're still 340 m from the pickup");

    // Closer now: the retry goes through.
    when(() => remote.arrived(any())).thenAnswer((_) async {});
    await cubit.markArrived();
    expect(cubit.state.phase, DriverPhase.arrived);
    expect(cubit.state.error, isNull);
    await cubit.close();
  });

  // ── Today's earnings on the offline sheet ─────────────────────────────────
  test("init loads today's earnings total for the offline sheet", () async {
    when(() => remote.earnings(range: 'today')).thenAnswer(
      (_) async => const DriverEarnings(total: 83.5, trips: 4, range: 'today'),
    );
    final cubit = make();
    await cubit.init('token');
    expect(cubit.state.lastEarned, 83.5);
    expect(cubit.state.phase, DriverPhase.offline);
    await cubit.close();
  });

  test('a failed earnings fetch on init is silent', () async {
    when(() => remote.earnings(range: any(named: 'range')))
        .thenThrow(const ApiException('nope', statusCode: 500));
    final cubit = make();
    await cubit.init('token');
    expect(cubit.state.lastEarned, isNull);
    expect(cubit.state.error, isNull);
    await cubit.close();
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

  group("rider's I'm on my way", () {
    final arrivedTrip = Trip(
      id: 'trip-1',
      status: TripStatus.arrived,
      tier: 'economy',
      pickup: const TripEndpoint(point: GeoPoint(12.96, 77.63), address: 'A'),
      dropoff: const TripEndpoint(point: GeoPoint(12.97, 77.59), address: 'B'),
    );

    test('shows for the pickup the driver is waiting at', () async {
      when(() => remote.getActiveTrip()).thenAnswer((_) async => arrivedTrip);
      final cubit = make();
      await cubit.init('token');
      await tick();
      expect(cubit.state.phase, DriverPhase.arrived);

      realtime.push('trip:rider_coming', {'tripId': 'trip-1'});
      await tick();
      expect(cubit.state.riderComingAt, isNotNull);
      await cubit.close();
    });

    test('is ignored for any other trip', () async {
      when(() => remote.getActiveTrip()).thenAnswer((_) async => arrivedTrip);
      final cubit = make();
      await cubit.init('token');
      await tick();

      realtime.push('trip:rider_coming', {'tripId': 'some-other-trip'});
      await tick();
      expect(cubit.state.riderComingAt, isNull);
      await cubit.close();
    });
  });

  group('stops on a ride', () {
    Trip onTrip({List<TripStop> stops = const []}) => Trip(
          id: 'trip-1',
          status: TripStatus.inProgress,
          tier: 'economy',
          pickup: const TripEndpoint(point: GeoPoint(41.30, 69.24), address: 'A'),
          dropoff: const TripEndpoint(point: GeoPoint(41.35, 69.28), address: 'B'),
          stops: stops,
        );
    const s1 = TripStop(point: GeoPoint(41.31, 69.25), address: 'Chorsu');
    const s2 = TripStop(point: GeoPoint(41.33, 69.26), address: 'Amir Temur');

    test('a stop the rider adds refreshes the trip and is announced', () async {
      var calls = 0;
      when(() => remote.getActiveTrip()).thenAnswer((_) async =>
          ++calls == 1 ? onTrip() : onTrip(stops: const [s1]));
      final cubit = make();
      await cubit.init('token');
      await tick();
      expect(cubit.state.trip?.stops, isEmpty);

      realtime.push('trip:stops_updated', {'tripId': 'trip-1'});
      await tick();
      expect(cubit.state.trip?.stops, [s1]);
      expect(cubit.state.stopsChangedAt, isNotNull);
      expect(cubit.state.stopsAhead, [s1]);
      await cubit.close();
    });

    test('stops are passed in order as the car reaches each one', () async {
      when(() => remote.getActiveTrip())
          .thenAnswer((_) async => onTrip(stops: const [s1, s2]));
      final cubit = make();
      await cubit.init('token');
      await tick();
      expect(cubit.state.phase, DriverPhase.onTrip);

      cubit.sendLocation(41.305, 69.245); // far from both
      expect(cubit.state.stopsAhead, [s1, s2]);
      cubit.sendLocation(41.3102, 69.2502); // ~27 m from Chorsu
      expect(cubit.state.stopsAhead, [s2]);
      cubit.sendLocation(41.3102, 69.2502); // still there: no double count
      expect(cubit.state.stopsAhead, [s2]);
      cubit.sendLocation(41.3301, 69.2601);
      expect(cubit.state.stopsAhead, isEmpty);
      await cubit.close();
    });
  });
}
