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
  Future<void> connectWith(AccessTokenProvider tokenProvider) async =>
      connect((await tokenProvider()) ?? '');
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
  Future<void> connectWith(AccessTokenProvider tokenProvider) async =>
      connect((await tokenProvider()) ?? '');

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
    'driver pings update the live ETA/distance along the approach leg',
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(
      phase: TripPhase.driverEnRoute,
      driver: AssignedDriver(
        name: 'Ava',
        rating: 4.9,
        etaSec: 55,
        etaDistanceM: 111,
      ),
      // Straight 111 m leg south along Biscayne Blvd (3 points).
      driverRoutePolyline: '_ki|C~ulhNbB?bB?',
    ),
    act: (c) {
      c.debugDriverLocation({'lat': 25.7760, 'lng': -80.1880});
      c.debugDriverLocation({'lat': 25.7752, 'lng': -80.1880});
    },
    expect: () => [
      isA<TripState>()
          .having((s) => s.liveRemainingM, 'remaining at start', closeTo(111, 8))
          .having((s) => s.liveEtaSec, 'eta at start', closeTo(55, 6)),
      isA<TripState>()
          .having((s) => s.liveRemainingM, 'remaining near end', lessThan(40))
          .having((s) => s.liveEtaSec, 'eta near end', lessThan(20)),
    ],
  );

  blocTest<TripCubit, TripState>(
    'driver pings prefer the server-routed etaSec/remainingM when present',
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(
      phase: TripPhase.driverEnRoute,
      driver: AssignedDriver(
        name: 'Ava',
        rating: 4.9,
        etaSec: 55,
        etaDistanceM: 111,
      ),
      driverRoutePolyline: '_ki|C~ulhNbB?bB?',
    ),
    act: (c) {
      // Server numbers win over the along-the-polyline estimate (~111 m).
      c.debugDriverLocation({
        'lat': 25.7760,
        'lng': -80.1880,
        'heading': 90,
        'speed': 8.2,
        'accuracy': 5,
        'ts': 1700000000000,
        'phase': 'approach',
        'etaSec': 240,
        'remainingM': 1850.4,
        'etaSource': 'route',
      });
      // A ping without them (older backend / no nav leg) falls back.
      c.debugDriverLocation({'lat': 25.7752, 'lng': -80.1880, 'etaSec': null});
    },
    expect: () => [
      isA<TripState>()
          .having((s) => s.liveEtaSec, 'server eta', 240)
          .having((s) => s.liveRemainingM, 'server remaining (rounded)', 1850)
          .having((s) => s.driverHeading, 'heading', 90)
          .having((s) => s.driverStale, 'stale', isFalse),
      isA<TripState>()
          .having((s) => s.liveRemainingM, 'client fallback', lessThan(40))
          .having((s) => s.liveEtaSec, 'client fallback eta', lessThan(20))
          .having((s) => s.driverHeading, 'heading kept', 90),
    ],
  );

  blocTest<TripCubit, TripState>(
    'trip:completed carries the itemised breakdown; the receipt copy wins',
    setUp: () {
      scripted = ScriptedRealtimeClient();
      when(() => repo.activeTripDetails()).thenAnswer((_) async => null);
      when(() => payments.receipt('t1')).thenAnswer((_) async => const Receipt(
            tripId: 't1',
            fare: 7.57,
            currency: 'USD',
            tip: 2,
            breakdown: FareBreakdown(
              baseFare: 2.5,
              distanceFare: 3.12,
              timeFare: 1.2,
              bookingFee: 1.75,
              surgeMultiplier: 1.2,
              promoDiscount: 1,
              tip: 2,
            ),
          ));
    },
    build: () => TripCubit(repo, scripted, payments, ratings),
    seed: () => TripState(phase: TripPhase.onTrip, trip: trip),
    act: (c) async {
      await c.init('token');
      scripted.push('trip:completed', {
        'tripId': 't1',
        'fareFinal': 7.57,
        'currency': 'USD',
        'breakdown': {
          'baseFare': 2.5,
          'distanceFare': 3.12,
          'timeFare': 1.2,
          'bookingFee': 1.75,
          'surgeMultiplier': 1.2,
          'promoDiscount': 1,
          'tip': 0,
        },
      });
      await Future<void>.delayed(Duration.zero);
    },
    expect: () => [
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.completed)
          .having((s) => s.fareFinal, 'fareFinal', 7.57)
          .having((s) => s.breakdown?.baseFare, 'base', 2.5)
          .having((s) => s.breakdown?.surgeMultiplier, 'surge', 1.2)
          .having((s) => s.breakdown?.promoDiscount, 'promo', 1)
          .having((s) => s.fareBreakdown?.tip, 'event tip', 0),
      isA<TripState>()
          .having((s) => s.receipt?.breakdown?.tip, 'receipt tip', 2)
          .having((s) => s.fareBreakdown?.tip, 'receipt copy wins', 2),
    ],
  );

  blocTest<TripCubit, TripState>(
    'trip:completed with a null breakdown keeps the two-line total',
    setUp: () {
      scripted = ScriptedRealtimeClient();
      when(() => repo.activeTripDetails()).thenAnswer((_) async => null);
      when(() => payments.receipt('t1')).thenAnswer((_) async =>
          const Receipt(tripId: 't1', fare: 7.57, currency: 'USD'));
    },
    build: () => TripCubit(repo, scripted, payments, ratings),
    seed: () => TripState(phase: TripPhase.onTrip, trip: trip),
    act: (c) async {
      await c.init('token');
      scripted.push('trip:completed',
          {'tripId': 't1', 'fareFinal': 7.57, 'breakdown': null});
      await Future<void>.delayed(Duration.zero);
    },
    expect: () => [
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.completed)
          .having((s) => s.fareBreakdown, 'no breakdown', isNull),
      isA<TripState>()
          .having((s) => s.receipt?.fare, 'receipt', 7.57)
          .having((s) => s.fareBreakdown, 'still none', isNull),
    ],
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
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
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
    'confirmRide sends the quoted fare + surge the rider saw (price lock)',
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
        stops: any(named: 'stops'),
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
      ),
    ).thenAnswer((_) async => trip),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(
      phase: TripPhase.choosingRide,
      pickup: pickup,
      dropoff: dropoff,
      estimate: estimate,
      selectedTier: 'xl',
    ),
    act: (c) => c.confirmRide(),
    verify: (_) => verify(
      () => repo.createTrip(
        pickup: any(named: 'pickup'),
        dropoff: any(named: 'dropoff'),
        tier: 'xl',
        pickupAddr: any(named: 'pickupAddr'),
        dropoffAddr: any(named: 'dropoffAddr'),
        promoCode: any(named: 'promoCode'),
        paymentMode: any(named: 'paymentMode'),
        paymentMethodId: any(named: 'paymentMethodId'),
        scheduledAt: any(named: 'scheduledAt'),
        stops: any(named: 'stops'),
        quotedFare: 246.63,
        quotedSurge: 1.0,
      ),
    ).called(1),
  );

  blocTest<TripCubit, TripState>(
    '409 PRICE_CHANGED re-prices the selected tier + surge and asks to '
    're-confirm instead of resetting',
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
        stops: any(named: 'stops'),
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
      ),
    ).thenThrow(const ApiException(
      'The price has changed (now 1.2x). Please confirm the new fare.',
      statusCode: 409,
      code: 'PRICE_CHANGED',
      body: {
        'statusCode': 409,
        'code': 'PRICE_CHANGED',
        'fare': 171.58,
        'surge': 1.2,
        'estimate': {
          'tier': 'economy',
          'fare': 171.58,
          'surge': 1.2,
          'currency': 'USD',
        },
      },
    )),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(
      phase: TripPhase.choosingRide,
      pickup: pickup,
      pickupAddr: 'A',
      dropoff: dropoff,
      dropoffAddr: 'B',
      estimate: estimate,
      selectedTier: 'economy',
      paymentMode: 'cash',
    ),
    act: (c) => c.confirmRide(),
    expect: () => [
      isA<TripState>().having((s) => s.phase, 'phase', TripPhase.requesting),
      isA<TripState>()
          .having((s) => s.phase, 'stays on ride options',
              TripPhase.choosingRide)
          .having((s) => s.estimate?.surge, 'surge updated', 1.2)
          .having((s) => s.selectedFare?.fare, 'selected fare updated', 171.58)
          .having((s) => s.selectedTier, 'tier kept', 'economy')
          // The other tier keeps its quote; route/addresses/payment survive.
          .having((s) => s.estimate?.tiers[1].fare, 'xl untouched', 246.63)
          .having((s) => s.estimate?.polyline, 'route kept', 'abcd')
          .having((s) => s.pickupAddr, 'pickup kept', 'A')
          .having((s) => s.paymentMode, 'payment kept', 'cash')
          .having((s) => s.trip, 'no trip', isNull)
          .having((s) => s.error, 'error',
              'Price updated to \$171.58 — tap Confirm to accept'),
    ],
  );

  blocTest<TripCubit, TripState>(
    'a 409 PRICE_CHANGED without a fare falls back to the server message',
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
        stops: any(named: 'stops'),
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
      ),
    ).thenThrow(const ApiException(
      'The price has changed.',
      statusCode: 409,
      code: 'PRICE_CHANGED',
      body: {'code': 'PRICE_CHANGED'},
    )),
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
          .having((s) => s.phase, 'phase', TripPhase.choosingRide)
          .having((s) => s.estimate, 'estimate unchanged', estimate)
          .having((s) => s.error, 'error', 'The price has changed.'),
    ],
  );

  blocTest<TripCubit, TripState>(
    'a re-confirm after PRICE_CHANGED sends the new quote and succeeds',
    setUp: () {
      var calls = 0;
      when(
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
          stops: any(named: 'stops'),
          quotedFare: any(named: 'quotedFare'),
          quotedSurge: any(named: 'quotedSurge'),
        ),
      ).thenAnswer((_) async {
        if (calls++ == 0) {
          throw const ApiException(
            'The price has changed.',
            statusCode: 409,
            code: 'PRICE_CHANGED',
            body: {'code': 'PRICE_CHANGED', 'fare': 150.5, 'surge': 1.1},
          );
        }
        return trip;
      });
    },
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(
      phase: TripPhase.choosingRide,
      pickup: pickup,
      dropoff: dropoff,
      estimate: estimate,
      selectedTier: 'economy',
    ),
    act: (c) async {
      await c.confirmRide();
      await c.confirmRide();
    },
    expect: () => [
      isA<TripState>().having((s) => s.phase, 'phase', TripPhase.requesting),
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.choosingRide)
          .having((s) => s.selectedFare?.fare, 'fare', 150.5),
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.requesting)
          .having((s) => s.error, 'prompt cleared', isNull),
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.searching)
          .having((s) => s.trip?.id, 'trip', 't1'),
    ],
    verify: (_) {
      verify(
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
          stops: any(named: 'stops'),
          quotedFare: 150.5,
          quotedSurge: 1.1,
        ),
      ).called(1);
    },
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
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
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
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
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
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
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
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
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
    'loadPaymentMethods falls back to cash when there is no card on file',
    setUp: () =>
        when(() => payments.methods()).thenAnswer((_) async => const []),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(paymentMode: 'card'),
    act: (c) => c.loadPaymentMethods(),
    expect: () => [
      isA<TripState>().having((s) => s.paymentMode, 'paymentMode', 'cash'),
    ],
  );

  blocTest<TripCubit, TripState>(
    'loadPaymentMethods keeps a chosen mode when cards exist',
    setUp: () => when(() => payments.methods()).thenAnswer(
      (_) async => [
        {'id': 'pm_1', 'brand': 'Visa', 'last4': '4242', 'isDefault': true},
      ],
    ),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => const TripState(paymentMode: 'cash'),
    act: (c) => c.loadPaymentMethods(),
    expect: () => [
      isA<TripState>().having((s) => s.paymentMode, 'paymentMode', 'cash'),
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
      when(() => repo.activeTripDetails()).thenAnswer(
        (_) async => ActiveTrip(
          trip: Trip(
            id: 't1',
            status: TripStatus.arrived,
            tier: 'economy',
            pickup: const TripEndpoint(point: pickup, address: '12 Pickup St'),
            dropoff: const TripEndpoint(point: dropoff, address: 'Dropoff Ave'),
            routePolyline: 'abcd',
            fareEstimate: 142.98,
          ),
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
    verify: (_) => verify(() => repo.activeTripDetails()).called(1),
  );

  // Cold-start restore with the server's driver keys (same shape as the
  // trip:accepted payload): the matched sheet shows the real driver + approach
  // leg after a relaunch instead of "—" until the next socket event.
  blocTest<TripCubit, TripState>(
    'init restores the assigned driver + approach route when the snapshot has them',
    setUp: () => when(() => repo.activeTripDetails()).thenAnswer(
      (_) async => ActiveTrip.fromJson(const {
        'id': 't1',
        'status': 'accepted',
        'tier': 'economy',
        'pickup': {'lat': 12.9611, 'lng': 77.6387},
        'dropoff': {'lat': 12.9674, 'lng': 77.5904},
        'driver': {'id': 'd1', 'name': 'Ava', 'rating': 4.9, 'phone': '+1305'},
        'vehicle': {'make': 'Toyota', 'model': 'Prius', 'plate': 'ABC123'},
        'etaSec': 240,
        'etaDistanceM': 1800,
        'driverPolyline': '_ki|C~ulhNbB?bB?',
      }),
    ),
    build: () => TripCubit(repo, realtime, payments, ratings),
    act: (c) => c.init('token'),
    expect: () => [
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.driverEnRoute)
          .having((s) => s.driver?.name, 'driver.name', 'Ava')
          .having((s) => s.driver?.plate, 'driver.plate', 'ABC123')
          .having((s) => s.driver?.phone, 'driver.phone', '+1305')
          .having((s) => s.driver?.etaSec, 'driver.etaSec', 240)
          .having((s) => s.driverRoutePolyline, 'approach polyline',
              '_ki|C~ulhNbB?bB?'),
    ],
  );

  // Regression: init() awaited connect() BEFORE subscribing, so a first
  // connect that threw (connect_error / 8 s timeout) left the session with no
  // listeners at all — deaf for good, even once socket.io's own retry landed.
  blocTest<TripCubit, TripState>(
    'init subscribes before connecting: a failed first connect is not deaf',
    setUp: () => when(() => repo.activeTripDetails()).thenAnswer(
      (_) async => ActiveTrip(
        trip: Trip(
          id: 't1',
          status: TripStatus.accepted,
          tier: 'economy',
          pickup: const TripEndpoint(point: pickup),
          dropoff: const TripEndpoint(point: dropoff),
        ),
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
        when(() => repo.activeTripDetails()).thenAnswer((_) async => null),
    build: () => TripCubit(repo, realtime, payments, ratings),
    act: (c) => c.init('token'),
    expect: () => const <TripState>[],
  );

  // Regression: iOS tears the socket down while the app is suspended and
  // socket.io's retry could stay wedged, leaving "Reconnecting…" up forever.
  blocTest<TripCubit, TripState>(
    'resumeFromBackground reconnects a dropped socket and re-syncs',
    setUp: () => when(() => repo.activeTripDetails()).thenAnswer(
      (_) async => ActiveTrip(
        trip: Trip(
          id: 't1',
          status: TripStatus.inProgress,
          tier: 'economy',
          pickup: const TripEndpoint(point: pickup),
          dropoff: const TripEndpoint(point: dropoff),
          fareEstimate: 142.98,
        ),
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

  // Regression: a cancel that failed on the wire (offline) used to reset the
  // UI to Home anyway, hiding a ride the server still had live.
  blocTest<TripCubit, TripState>(
    'cancelTrip keeps the ride + surfaces an error when the REST cancel fails',
    setUp: () =>
        when(() => repo.cancelTrip(any(), reason: any(named: 'reason')))
            .thenThrow(const ApiException('offline', statusCode: 0)),
    build: () => TripCubit(repo, realtime, payments, ratings),
    seed: () => TripState(
      phase: TripPhase.driverEnRoute,
      trip: trip,
      driver: const AssignedDriver(name: 'Ava', rating: 4.9),
    ),
    act: (c) async {
      expect(await c.cancelTrip(), 0);
      // Still cancellable: a second tap reaches the backend again.
      await c.cancelTrip();
    },
    expect: () => [
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.driverEnRoute)
          .having((s) => s.trip?.id, 'trip kept', 't1')
          .having((s) => s.error, 'error', TripCubit.cancelFailedMessage),
      // Second attempt clears the message, then fails again.
      isA<TripState>().having((s) => s.error, 'error cleared', isNull),
      isA<TripState>()
          .having((s) => s.error, 'error', TripCubit.cancelFailedMessage),
    ],
    verify: (_) =>
        verify(() => repo.cancelTrip('t1', reason: any(named: 'reason')))
            .called(2),
  );

  blocTest<TripCubit, TripState>(
    'trip:cancelled from the driver goes idle with the reason surfaced',
    setUp: () =>
        when(() => repo.activeTripDetails()).thenAnswer((_) async => null),
    build: () => TripCubit(
        repo, scripted = ScriptedRealtimeClient(), payments, ratings),
    seed: () => TripState(
      phase: TripPhase.driverEnRoute,
      trip: trip,
      driver: const AssignedDriver(name: 'Ava', rating: 4.9),
    ),
    act: (c) async {
      await c.init('token');
      scripted.push('trip:cancelled',
          {'tripId': 't1', 'by': 'driver', 'reason': 'Rider no-show'});
    },
    expect: () => [
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.idle)
          .having((s) => s.trip, 'trip', isNull)
          .having((s) => s.driver, 'driver', isNull)
          .having((s) => s.error, 'error',
              '${TripCubit.driverCancelledMessage} — Rider no-show'),
    ],
  );

  blocTest<TripCubit, TripState>(
    'trip:cancelled for another trip id is ignored',
    setUp: () =>
        when(() => repo.activeTripDetails()).thenAnswer((_) async => null),
    build: () => TripCubit(
        repo, scripted = ScriptedRealtimeClient(), payments, ratings),
    seed: () => TripState(phase: TripPhase.driverEnRoute, trip: trip),
    act: (c) async {
      await c.init('token');
      scripted.push('trip:cancelled', {'tripId': 'other', 'by': 'driver'});
    },
    expect: () => const <TripState>[],
  );

  blocTest<TripCubit, TripState>(
    'trip:otp_locked surfaces the lock on the matched sheet',
    setUp: () =>
        when(() => repo.activeTripDetails()).thenAnswer((_) async => null),
    build: () => TripCubit(
        repo, scripted = ScriptedRealtimeClient(), payments, ratings),
    seed: () => TripState(phase: TripPhase.driverArrived, trip: trip),
    act: (c) async {
      await c.init('token');
      scripted.push('trip:otp_locked', {'tripId': 't1', 'lockSeconds': 900});
    },
    expect: () => [
      isA<TripState>()
          .having((s) => s.phase, 'phase', TripPhase.driverArrived)
          .having((s) => s.error, 'error', TripCubit.otpLockedMessage),
    ],
  );

  blocTest<TripCubit, TripState>(
    'trip:payment_warning becomes a one-shot notice, cleared once shown',
    setUp: () =>
        when(() => repo.activeTripDetails()).thenAnswer((_) async => null),
    build: () => TripCubit(
        repo, scripted = ScriptedRealtimeClient(), payments, ratings),
    seed: () => TripState(phase: TripPhase.onTrip, trip: trip),
    act: (c) async {
      await c.init('token');
      scripted.push('trip:payment_warning',
          {'tripId': 't1', 'message': 'Payment could not be processed'});
      c.clearNotice();
    },
    expect: () => [
      isA<TripState>()
          .having((s) => s.notice, 'notice', 'Payment could not be processed')
          .having((s) => s.phase, 'phase unchanged', TripPhase.onTrip),
      isA<TripState>().having((s) => s.notice, 'notice cleared', isNull),
    ],
  );

  blocTest<TripCubit, TripState>(
    'driver pings store heading + seen-at; silence flags the driver stale',
    build: () => TripCubit(repo, realtime, payments, ratings,
        staleAfter: const Duration(milliseconds: 40)),
    seed: () => const TripState(phase: TripPhase.driverEnRoute),
    act: (c) => c.debugDriverLocation(
        {'lat': 25.7760, 'lng': -80.1880, 'heading': 182.5}),
    wait: const Duration(milliseconds: 120),
    expect: () => [
      isA<TripState>()
          .having((s) => s.driverHeading, 'heading', 182.5)
          .having((s) => s.driverSeenAt, 'seenAt', isNotNull)
          .having((s) => s.driverStale, 'stale', isFalse),
      isA<TripState>().having((s) => s.driverStale, 'stale', isTrue),
    ],
  );

  blocTest<TripCubit, TripState>(
    'the next ping clears the stale flag and keeps the last heading',
    build: () => TripCubit(repo, realtime, payments, ratings,
        staleAfter: const Duration(seconds: 30)),
    seed: () => const TripState(
      phase: TripPhase.driverEnRoute,
      driverHeading: 90,
      driverStale: true,
    ),
    act: (c) => c.debugDriverLocation({'lat': 25.7760, 'lng': -80.1880}),
    expect: () => [
      isA<TripState>()
          .having((s) => s.driverStale, 'stale', isFalse)
          .having((s) => s.driverHeading, 'heading kept', 90),
    ],
  );

  blocTest<TripCubit, TripState>(
    'closing the cubit cancels the stale watchdog',
    build: () => TripCubit(repo, realtime, payments, ratings,
        staleAfter: const Duration(milliseconds: 20)),
    seed: () => const TripState(phase: TripPhase.driverEnRoute),
    act: (c) async {
      c.debugDriverLocation({'lat': 25.7760, 'lng': -80.1880});
      await c.close();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    },
    expect: () => [
      isA<TripState>().having((s) => s.driverStale, 'stale', isFalse),
    ],
  );
}
