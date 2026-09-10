import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repo;

  const user = AppUser(id: 'u1', phone: '+19876543210', role: 'rider');

  setUp(() {
    repo = MockAuthRepository();
  });

  group('AuthBloc', () {
    blocTest<AuthBloc, AuthState>(
      'AuthStarted with a stored session -> authenticated',
      setUp: () => when(repo.restoreSession).thenAnswer((_) async => user),
      build: () => AuthBloc(repo),
      act: (bloc) => bloc.add(const AuthStarted()),
      expect: () => [
        const AuthState(status: AuthStatus.authenticated, user: user),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthStarted with no session -> unauthenticated',
      setUp: () => when(repo.restoreSession).thenAnswer((_) async => null),
      build: () => AuthBloc(repo),
      act: (bloc) => bloc.add(const AuthStarted()),
      expect: () => [
        const AuthState(status: AuthStatus.unauthenticated),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthOtpRequested -> busy then codeSent with devCode',
      setUp: () =>
          when(() => repo.requestOtp(any())).thenAnswer((_) async => '1234'),
      build: () => AuthBloc(repo),
      act: (bloc) => bloc.add(const AuthOtpRequested('+19876543210')),
      expect: () => [
        const AuthState(busy: true, phone: '+19876543210'),
        const AuthState(
          status: AuthStatus.codeSent,
          phone: '+19876543210',
          devCode: '1234',
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthOtpSubmitted with a phone in state -> authenticated',
      setUp: () => when(() => repo.verifyOtp(any(), any()))
          .thenAnswer((_) async => user),
      build: () => AuthBloc(repo),
      seed: () => const AuthState(
        status: AuthStatus.codeSent,
        phone: '+19876543210',
        devCode: '1234',
      ),
      act: (bloc) => bloc.add(const AuthOtpSubmitted('1234')),
      expect: () => [
        const AuthState(
          status: AuthStatus.codeSent,
          phone: '+19876543210',
          devCode: '1234',
          busy: true,
        ),
        const AuthState(
          status: AuthStatus.authenticated,
          phone: '+19876543210',
          user: user,
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'AuthOtpRequested surfaces an ApiException as an error',
      setUp: () => when(() => repo.requestOtp(any()))
          .thenThrow(const ApiException('Too many requests')),
      build: () => AuthBloc(repo),
      act: (bloc) => bloc.add(const AuthOtpRequested('+19876543210')),
      expect: () => [
        const AuthState(busy: true, phone: '+19876543210'),
        const AuthState(phone: '+19876543210', error: 'Too many requests'),
      ],
    );

    group('session expiry', () {
      late StreamController<void> expired;

      setUp(() => expired = StreamController<void>.broadcast());
      tearDown(() => expired.close());

      blocTest<AuthBloc, AuthState>(
        'a sessionExpired tick while authenticated -> unauthenticated',
        build: () => AuthBloc(repo, sessionExpired: expired.stream),
        seed: () =>
            const AuthState(status: AuthStatus.authenticated, user: user),
        act: (_) => expired.add(null),
        expect: () => [
          const AuthState(status: AuthStatus.unauthenticated),
        ],
      );

      blocTest<AuthBloc, AuthState>(
        'AuthSessionExpired is ignored while not signed in (codeSent)',
        build: () => AuthBloc(repo, sessionExpired: expired.stream),
        seed: () => const AuthState(
          status: AuthStatus.codeSent,
          phone: '+19876543210',
        ),
        act: (bloc) {
          expired.add(null);
          bloc.add(const AuthSessionExpired());
        },
        expect: () => <AuthState>[],
      );
    });
  });
}
