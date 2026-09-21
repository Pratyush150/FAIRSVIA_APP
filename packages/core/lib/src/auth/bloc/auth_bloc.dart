import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_models/shared_models.dart';

import '../../network/api_exception.dart';
import '../auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

/// Drives the phone-OTP login flow and holds the authenticated user.
/// Shared by all three apps; each app only supplies the post-login UI.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  /// [sessionExpired] is the network layer's "refresh failed, tokens cleared"
  /// signal (see `DioClient.sessionExpired`); each tick becomes an
  /// [AuthSessionExpired] event.
  AuthBloc(this._repository, {Stream<void>? sessionExpired})
      : super(const AuthState()) {
    on<AuthStarted>(_onStarted);
    on<AuthOtpRequested>(_onOtpRequested);
    on<AuthOtpSubmitted>(_onOtpSubmitted);
    on<AuthBackToPhone>(_onBackToPhone);
    on<AuthProfileCompleted>(
      (event, emit) => emit(state.copyWith(user: event.user)),
    );
    on<AuthSignedOut>(_onSignedOut);
    on<AuthSessionExpired>(_onSessionExpired);
    _sessionExpiredSub =
        sessionExpired?.listen((_) => add(const AuthSessionExpired()));
  }

  final AuthRepository _repository;
  StreamSubscription<void>? _sessionExpiredSub;

  @override
  Future<void> close() async {
    await _sessionExpiredSub?.cancel();
    return super.close();
  }

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    final user = await _repository.restoreSession();
    emit(
      user != null
          ? state.copyWith(status: AuthStatus.authenticated, user: user)
          : state.copyWith(status: AuthStatus.unauthenticated),
    );
  }

  Future<void> _onOtpRequested(
    AuthOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(busy: true, error: null, phone: event.phone));
    try {
      final devCode = await _repository.requestOtp(event.phone);
      emit(state.copyWith(
        status: AuthStatus.codeSent,
        busy: false,
        devCode: devCode,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  Future<void> _onOtpSubmitted(
    AuthOtpSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    final phone = state.phone;
    if (phone == null) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      final user = await _repository.verifyOtp(phone, event.code);
      emit(state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        busy: false,
        devCode: null,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  void _onBackToPhone(AuthBackToPhone event, Emitter<AuthState> emit) {
    emit(state.copyWith(
      status: AuthStatus.unauthenticated,
      error: null,
      devCode: null,
    ));
  }

  Future<void> _onSignedOut(
    AuthSignedOut event,
    Emitter<AuthState> emit,
  ) async {
    await _repository.signOut();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  void _onSessionExpired(AuthSessionExpired event, Emitter<AuthState> emit) {
    // Only a signed-in session can expire. During sign-in (codeSent) a stray
    // 401 must not bounce the user off the OTP screen.
    if (state.status != AuthStatus.authenticated) return;
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }
}
