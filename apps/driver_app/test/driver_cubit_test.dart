import 'dart:async';

import 'package:core/core.dart';
import 'package:driver_app/features/driver/driver_cubit.dart';
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

  @override
  Future<void> connect(String token) async => _connected = true;

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

  setUp(() {
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
    final cubit = DriverCubit(realtime, remote, ratings);
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
    final cubit = DriverCubit(realtime, remote, ratings);
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
    final cubit = DriverCubit(realtime, remote, ratings);
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

    final cubit = DriverCubit(realtime, remote, ratings);
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

    final cubit = DriverCubit(realtime, remote, ratings);
    await cubit.init('token');
    await tick();

    expect(cubit.state.phase, DriverPhase.onTrip);
    expect(cubit.state.trip?.id, 'trip-1');

    await cubit.close();
  });

  test('rider cancellation after assignment resets the driver', () async {
    final cubit = DriverCubit(realtime, remote, ratings);
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
    final cubit = DriverCubit(realtime, remote, ratings);
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
    final cubit = DriverCubit(realtime, remote, ratings);
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
}
