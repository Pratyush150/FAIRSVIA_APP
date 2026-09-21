import 'dart:async';

import 'package:core/core.dart';
import 'package:driver_app/features/driver/driver_cubit.dart';
import 'package:driver_app/features/driver/location_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDriverRemote extends Mock implements DriverRemoteDataSource {}

class MockRatings extends Mock implements RatingsRemoteDataSource {}

/// Minimal in-memory socket: enough for goOnline/goOffline and the presence
/// poll, which never touch the wire beyond `emit`.
class _Realtime implements RealtimeClient {
  final _controllers = <String, StreamController<Map<String, dynamic>>>{};
  final List<(String, Map<String, dynamic>)> emitted = [];
  bool _connected = false;

  @override
  Future<void> connect(String token) async => _connected = true;

  @override
  Future<void> connectWith(AccessTokenProvider tokenProvider) async =>
      _connected = true;

  @override
  void disconnect() => _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<Map<String, dynamic>> on(String event) => _controllers
      .putIfAbsent(
          event, () => StreamController<Map<String, dynamic>>.broadcast())
      .stream;

  @override
  Stream<void> get reconnects => const Stream.empty();

  @override
  Stream<bool> get connection => const Stream.empty();

  @override
  void emit(String event, Map<String, dynamic> data) =>
      emitted.add((event, data));
}

DriverProfile _profile(String status) => DriverProfile(
      status: status,
      vehicleMake: 'Toyota',
      vehicleModel: 'Camry',
      plateNumber: 'FLA 1234',
      vehicleTier: 'economy',
      docsVerified: true,
    );

void main() {
  late _Realtime realtime;
  late MockDriverRemote remote;

  DriverCubit make() => DriverCubit(
        realtime,
        remote,
        MockRatings(),
        checkLocation: () async => LocationAccess.granted,
        presenceInterval: const Duration(milliseconds: 20),
      );

  setUp(() {
    realtime = _Realtime();
    remote = MockDriverRemote();
    when(() => remote.setStatus(any())).thenAnswer((_) async {});
  });

  group('presence re-sync', () {
    test('two consecutive server "offline" answers flip the UI offline',
        () async {
      when(() => remote.me()).thenAnswer((_) async => _profile('offline'));
      final cubit = make();
      await cubit.goOnline();
      expect(cubit.state.isOnline, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      // One strike is not enough (a poll can race our own go-online).
      expect(cubit.state.isOnline, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(cubit.state.isOnline, isFalse);
      expect(cubit.state.error, contains('no longer has you online'));
      await cubit.close();
    });

    test('an online answer resets the strike count', () async {
      final answers = ['offline', 'online', 'offline', 'online'];
      var i = 0;
      when(() => remote.me())
          .thenAnswer((_) async => _profile(answers[i++ % answers.length]));
      final cubit = make();
      await cubit.goOnline();
      await Future<void>.delayed(const Duration(milliseconds: 110));
      expect(cubit.state.isOnline, isTrue);
      await cubit.close();
    });

    test('polling stops after going offline', () async {
      when(() => remote.me()).thenAnswer((_) async => _profile('online'));
      final cubit = make();
      await cubit.goOnline();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await cubit.goOffline();
      final before = verify(() => remote.me()).callCount;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      verifyNever(() => remote.me());
      expect(before, greaterThan(0));
      await cubit.close();
    });

    test('a failing poll is ignored', () async {
      when(() => remote.me()).thenThrow(const ApiException('boom'));
      final cubit = make();
      await cubit.goOnline();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(cubit.state.isOnline, isTrue);
      await cubit.close();
    });
  });

  group('onboard', () {
    test('returns false and keeps the message when the server rejects',
        () async {
      when(() => remote.onboarding(
            vehicleMake: any(named: 'vehicleMake'),
            vehicleModel: any(named: 'vehicleModel'),
            plateNumber: any(named: 'plateNumber'),
            vehicleTier: any(named: 'vehicleTier'),
            vehicleColor: any(named: 'vehicleColor'),
            licenseNo: any(named: 'licenseNo'),
          )).thenThrow(const ApiException('vehicleMake should not be empty'));
      final cubit = make();
      final ok = await cubit.onboard(
          make: '', model: 'Camry', plate: 'FLA 1234', tier: 'economy');
      expect(ok, isFalse);
      expect(cubit.state.error, contains('vehicleMake'));
      expect(cubit.state.isOnline, isFalse);
      await cubit.close();
    });

    test('goOnlineAfter=false saves without touching presence', () async {
      when(() => remote.onboarding(
            vehicleMake: any(named: 'vehicleMake'),
            vehicleModel: any(named: 'vehicleModel'),
            plateNumber: any(named: 'plateNumber'),
            vehicleTier: any(named: 'vehicleTier'),
            vehicleColor: any(named: 'vehicleColor'),
            licenseNo: any(named: 'licenseNo'),
          )).thenAnswer((_) async {});
      final cubit = make();
      final ok = await cubit.onboard(
        make: 'Honda',
        model: 'Civic',
        plate: 'ABC 123',
        tier: 'comfort',
        color: 'Blue',
        goOnlineAfter: false,
      );
      expect(ok, isTrue);
      expect(cubit.state.isOnline, isFalse);
      verifyNever(() => remote.setStatus(any()));
      await cubit.close();
    });
  });
}
