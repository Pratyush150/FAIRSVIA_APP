import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:shared_models/shared_models.dart';

class MockTripRepository extends Mock implements TripRepository {}

class MockPayments extends Mock implements PaymentsRemoteDataSource {}

class MockRatings extends Mock implements RatingsRemoteDataSource {}

/// No-op realtime client; these tests exercise the request flow, not sockets.
class FakeRealtimeClient implements RealtimeClient {
  @override
  Future<void> connect(String token) async {}
  @override
  void disconnect() {}
  @override
  bool get isConnected => false;
  @override
  Stream<Map<String, dynamic>> on(String event) => const Stream.empty();
  @override
  Stream<void> get reconnects => const Stream.empty();
  @override
  Stream<bool> get connection => const Stream.empty();
  @override
  void emit(String event, Map<String, dynamic> data) {}
}

/// Realtime fake with pushable per-event streams, so tests can prove the
/// cubit's subscriptions exist (and fire) regardless of what connect() did.
class ScriptedRealtimeClient implements RealtimeClient {
  ScriptedRealtimeClient({this.failConnect = false});

  final bool failConnect;
  final _events = <String, StreamController<Map<String, dynamic>>>{};
  final _connection = StreamController<bool>.broadcast(sync: true);
  int connectCalls = 0;

  @override
  Future<void> connect(String token) async {
    connectCalls++;
    if (failConnect) throw TimeoutException('socket connect timeout');
  }

  @override
  void disconnect() {}
  @override
  bool get isConnected => false;
  @override
  Stream<Map<String, dynamic>> on(String event) => _events
      .putIfAbsent(
          event, () => StreamController<Map<String, dynamic>>.broadcast(sync: true))
      .stream;
  @override
  Stream<void> get reconnects => const Stream.empty();
  @override
  Stream<bool> get connection => _connection.stream;
  @override
  void emit(String event, Map<String, dynamic> data) {}

  /// Deliver a server event. Silently dropped when nobody ever subscribed to
  /// [event] — exactly the "deaf session" failure this guards against.
  void push(String event, Map<String, dynamic> data) =>
      _events[event]?.add(data);

  void setConnected(bool up) => _connection.add(up);
}

void main() {
  late MockTripRepository repo;
  late MockPayments payments;
  late MockRatings ratings;
  final realtime = FakeRealtimeClient();
  late ScriptedRealtimeClient scripted;

  const pickup = GeoPoint(12.9611, 77.6387);
  const dropoff = GeoPoint(12.9674, 77.5904);

  const estimate = TripEstimate(
    distanceM: 6865,
    durationS: 824,
    polyline: 'abcd',
    surge: 1,
    currency: 'USD',
    pickup: pickup,
    dropoff: dropoff,
    tiers: [
      FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 142.98,
        currency: 'USD',
        etaSeconds: 824,
      ),
      FareTier(
        tier: 'xl',
        label: 'XL',
        capacity: 6,
        fare: 246.63,
        currency: 'USD',
        etaSeconds: 824,
      ),
    ],
  );

  final trip = Trip(
    id: 't1',
    status: TripStatus.requested,
    tier: 'economy',
    pickup: const TripEndpoint(point: pickup),
    dropoff: const TripEndpoint(point: dropoff),
    fareEstimate: 142.98,
  );

  setUpAll(() {
    // Required by mocktail for any()/captureAny() on the custom GeoPoint type.
    registerFallbackValue(const GeoPoint(0, 0));
  });

  setUp(() {
    repo = MockTripRepository();
    payments = MockPayments();
    ratings = MockRatings();
  });

  blocTest<TripCubit, TripState>(
    'chooseDestination -> loadingEstimate then choosingRide with default tier',
    setUp: () => when(() => repo.estimate(any(), any()))
        .thenAnswer((_) async => estimate),
    build: () => TripCubit(repo, realtime, payments, ratings),
    act: (c) => c.chooseDestination(pickup: pickup, dropoff: dropoff),
    expect: () => [
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.loadingEstimate),
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.choosingRide)
          .having((s) => s.selectedTier, 'selectedTier', 'economy')
          .having((s) => s.estimate, 'estimate', estimate),
    ],
  );

  blocTest<TripCubit, TripState>(
    'cancelTrip after a no-drivers bounce keeps the ride options',
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(
      phase: TripPhase.choosingRide,
      estimate: estimate,
      selectedTier: 'economy',
      error: 'No drivers available nearby right now — try again.',
    ),
    act: (c) => c.cancelTrip(),
    expect: () => <TripState>[],
    verify: (_) => verifyNever(() => repo.cancelTrip(any(), reason: any(named: 'reason'))),
  );

  blocTest<TripCubit, TripState>(
    'selectTier updates the selected tier',
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(
      phase: TripPhase.choosingRide,
      estimate: estimate,
      selectedTier: 'economy',
    ),
    act: (c) => c.selectTier('xl'),
    expect: () => [
      isA<TripState>().having((s) => s.selectedTier, 'selectedTier', 'xl'),
    ],
  );

  blocTest<TripCubit, TripState>(
    'confirmRide -> requesting then searching with the created trip',
    setUp: () => when(
      () => repo.createTrip(
        pickup: any(named: 'pickup'),
        dropoff: any(named: 'dropoff'),
        tier: any(named: 'tier'),
        pickupAddr: any(named: 'pickupAddr'),
        dropoffAddr: any(named: 'dropoffAddr'),
        promoCode: any(named: 'promoCode'),
        paymentMode: any(named: 'paymentMode'),
        scheduledAt: any(named: 'scheduledAt'),
      ),
    ).thenAnswer((_) async => trip),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(
      phase: TripPhase.choosingRide,
      pickup: pickup,
      dropoff: dropoff,
      estimate: estimate,
      selectedTier: 'economy',
    ),
    act: (c) => c.confirmRide(),
    expect: () => [
      isA<TripState>().having((s) => s.phase, 'phase', TripPhase.requesting),
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.searching)
          .having((s) => s.trip?.id, 'trip.id', 't1'),
    ],
  );

  blocTest<TripCubit, TripState>(
    'selectPaymentCard sets card mode + id; confirmRide passes paymentMethodId',
    setUp: () => when(
      () => repo.createTrip(
        pickup: any(named: 'pickup'),
        dropoff: any(named: 'dropoff'),
        tier: any(named: 'tier'),
        pickupAddr: any(named: 'pickupAddr'),
        dropoffAddr: any(named: 'dropoffAddr'),
        promoCode: any(named: 'promoCode'),
        paymentMode: any(named: 'paymentMode'),
        paymentMethodId: any(named: 'paymentMethodId'),
        scheduledAt: any(named: 'scheduledAt'),
      ),
    ).thenAnswer((_) async => trip),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(
      phase: TripPhase.choosingRide,
      pickup: pickup,
      dropoff: dropoff,
      estimate: estimate,
      selectedTier: 'economy',
    ),
    act: (c) {
      c.selectPaymentCard('pm_1');
      c.confirmRide();
    },
    verify: (_) => verify(
      () => repo.createTrip(
        pickup: any(named: 'pickup'),
        dropoff: any(named: 'dropoff'),
        tier: any(named: 'tier'),
        pickupAddr: any(named: 'pickupAddr'),
        dropoffAddr: any(named: 'dropoffAddr'),
        promoCode: any(named: 'promoCode'),
        paymentMode: 'card',
        paymentMethodId: 'pm_1',
        scheduledAt: any(named: 'scheduledAt'),
      ),
    ).called(1),
  );

  blocTest<TripCubit, TripState>(
    'switching to cash clears the chosen card so no paymentMethodId is sent',
    setUp: () => when(
      () => repo.createTrip(
        pickup: any(named: 'pickup'),
        dropoff: any(named: 'dropoff'),
        tier: any(named: 'tier'),
        pickupAddr: any(named: 'pickupAddr'),
        dropoffAddr: any(named: 'dropoffAddr'),
        promoCode: any(named: 'promoCode'),
        paymentMode: any(named: 'paymentMode'),
        paymentMethodId: any(named: 'paymentMethodId'),
        scheduledAt: any(named: 'scheduledAt'),
      ),
    ).thenAnswer((_) async => trip),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(
      phase: TripPhase.choosingRide,
      pickup: pickup,
      dropoff: dropoff,
      estimate: estimate,
      selectedTier: 'economy',
      paymentMode: 'card',
      selectedMethodId: 'pm_1',
    ),
    act: (c) {
      c.setPaymentMode('cash');
      c.confirmRide();
    },
    verify: (_) => verify(
      () => repo.createTrip(
        pickup: any(named: 'pickup'),
        dropoff: any(named: 'dropoff'),
        tier: any(named: 'tier'),
        pickupAddr: any(named: 'pickupAddr'),
        dropoffAddr: any(named: 'dropoffAddr'),
        promoCode: any(named: 'promoCode'),
        paymentMode: 'cash',
        paymentMethodId: null,
        scheduledAt: any(named: 'scheduledAt'),
      ),
    ).called(1),
  );

  blocTest<TripCubit, TripState>(
    'loadPaymentMethods stores the saved cards on state',
    setUp: () => when(() => payments.methods()).thenAnswer(
      (_) async => [
        {'id': 'pm_1', 'brand': 'Visa', 'last4': '4242', 'isDefault': true},
      ],
    ),
    build: () => TripCubit(repo, realtime, payments, ratings),
    act: (c) => c.loadPaymentMethods(),
    expect: () => [
      isA<TripState>().having(
        (s) => s.paymentMethods.first['last4'],
        'first card last4',
        '4242',
      ),
    ],
  );

  blocTest<TripCubit, TripState>(
    'cancelTrip cancels on the backend and resets to idle',
    setUp: () =>
        when(() => repo.cancelTrip(any(), reason: any(named: 'reason')))
            .thenAnswer((_) async => 0.0),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => TripState(phase: TripPhase.searching, trip: trip),
    act: (c) => c.cancelTrip(),
    expect: () => [
      isA<TripState>().having((s) => s.phase, 'phase', TripPhase.idle),
    ],
    verify: (_) =>
        verify(() => repo.cancelTrip('t1', reason: any(named: 'reason')))
            .called(1),
  );

  blocTest<TripCubit, TripState>(
    'tipDriver posts the tip and records the amount',
    setUp: () =>
        when(() => payments.tip('t1', 30)).thenAnswer((_) async => 30),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => TripState(phase: TripPhase.completed, trip: trip),
    act: (c) => c.tipDriver(30),
    expect: () => [
      isA<TripState>().having((s) => s.tipping, 'tipping', true),
      isA<TripState>()
          .having((s) => s.tipping, 'tipping', false)
          .having((s) => s.tipAmount, 'tipAmount', 30),
    ],
    verify: (_) => verify(() => payments.tip('t1', 30)).called(1),
  );

  blocTest<TripCubit, TripState>(
    'rateDriver submits the rating and records the stars',
    setUp: () => when(() => ratings.rate('t1',
        stars: any(named: 'stars'),
        comment: any(named: 'comment'))).thenAnswer((_) async {}),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => TripState(phase: TripPhase.completed, trip: trip),
    act: (c) => c.rateDriver(5),
    expect: () => [
      isA<TripState>().having((s) => s.rating, 'rating', 5),
    ],
    verify: (_) => verify(() => ratings.rate('t1', stars: 5, comment: null))
        .called(1),
  );

  // Regression: killing the app mid-ride used to drop the rider on the idle
  // "Where to?" home while a driver was actually en route, because init() only
  // subscribed to socket events and never asked the server for a live trip.
  blocTest<TripCubit, TripState>(
    'init restores an in-flight trip after a cold start',
    setUp: () {
      when(() => repo.activeTrip()).thenAnswer(
        (_) async => Trip(
          id: 't1',
          status: TripStatus.arrived,
          tier: 'economy',
          pickup: const TripEndpoint(point: pickup, address: '12 Pickup St'),
          dropoff: const TripEndpoint(point: dropoff, address: 'Dropoff Ave'),
          routePolyline: 'abcd',
          fareEstimate: 142.98,
        ),
      );
    },
    build: () => TripCubit(repo, realtime, payments, ratings),
    act: (c) => c.init('token'),
    expect: () => [
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.driverArrived)
          .having((s) => s.trip?.id, 'trip.id', 't1')
          // Regression: only phase+trip were restored, so the map had no
          // pickup/dropoff markers and the sheets showed an empty address.
          .having((s) => s.pickup, 'pickup', pickup)
          .having((s) => s.dropoff, 'dropoff', dropoff)
          .having((s) => s.pickupAddr, 'pickupAddr', '12 Pickup St')
          .having((s) => s.dropoffAddr, 'dropoffAddr', 'Dropoff Ave')
          .having((s) => s.trip?.routePolyline, 'trip.routePolyline', 'abcd')
          // The driver isn't part of the Trip model: must stay unknown, not
          // be fabricated.
          .having((s) => s.driver, 'driver', isNull),
    ],
    verify: (_) => verify(() => repo.activeTrip()).called(1),
  );

  // Regression: init() awaited connect() BEFORE subscribing, so a first
  // connect that threw (connect_error / 8 s timeout) left the session with no
  // listeners at all — deaf for good, even once socket.io's own retry landed.
  blocTest<TripCubit, TripState>(
    'init subscribes before connecting: a failed first connect is not deaf',
    setUp: () => when(() => repo.activeTrip()).thenAnswer(
      (_) async => Trip(
        id: 't1',
        status: TripStatus.accepted,
        tier: 'economy',
        pickup: const TripEndpoint(point: pickup),
        dropoff: const TripEndpoint(point: dropoff),
      ),
    ),
    build: () => TripCubit(
        repo, scripted = ScriptedRealtimeClient(failConnect: true), payments, ratings),
    act: (c) async {
      await c.init('token');
      // The socket.io retry eventually lands and events flow again.
      scripted.setConnected(true);
      scripted.push('trip:arrived', {});
    },
    expect: () => [
      // The failed connect is surfaced, not swallowed.
      isA<TripState>().having((s) => s.connected, 'connected', false),
      // Restore still ran (REST) despite the dead socket.
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.driverEnRoute)
          .having((s) => s.connected, 'connected', false),
      isA<TripState>().having((s) => s.connected, 'connected', true),
      // …and the event subscription registered before connect() fires.
      isA<TripState>().having((s) => s.phase, 'phase', TripPhase.driverArrived),
    ],
    verify: (_) => expect(scripted.connectCalls, 1),
  );

  blocTest<TripCubit, TripState>(
    'init stays idle when there is no active trip',
    setUp: () =>
        when(() => repo.activeTrip()).thenAnswer((_) async => null),
    build: () => TripCubit(repo, realtime, payments, ratings),
    act: (c) => c.init('token'),
    expect: () => const <TripState>[],
  );

  // Regression: iOS tears the socket down while the app is suspended and
  // socket.io's retry could stay wedged, leaving "Reconnecting…" up forever.
  blocTest<TripCubit, TripState>(
    'resumeFromBackground reconnects a dropped socket and re-syncs',
    setUp: () => when(() => repo.activeTrip()).thenAnswer(
      (_) async => Trip(
        id: 't1',
        status: TripStatus.inProgress,
        tier: 'economy',
        pickup: const TripEndpoint(point: pickup),
        dropoff: const TripEndpoint(point: dropoff),
        fareEstimate: 142.98,
      ),
    ),
    build: () => TripCubit(repo, realtime, payments, ratings),
    // FakeRealtimeClient reports isConnected == false, i.e. the suspended case.
    act: (c) => c.resumeFromBackground('token'),
    expect: () => [
      isA<TripState>().having((s) => s.connected, 'connected', true),
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.onTrip)
          .having((s) => s.trip?.id, 'trip.id', 't1'),
    ],
  );
}
