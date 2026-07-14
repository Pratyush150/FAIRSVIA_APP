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

void main() {
  late MockTripRepository repo;
  late MockPayments payments;
  late MockRatings ratings;
  final realtime = FakeRealtimeClient();

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
    'cancelTrip cancels on the backend and resets to idle',
    setUp: () =>
        when(() => repo.cancelTrip(any(), reason: any(named: 'reason')))
            .thenAnswer((_) async {}),
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
}
