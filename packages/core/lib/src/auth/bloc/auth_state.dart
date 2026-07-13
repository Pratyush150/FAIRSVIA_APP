part of 'auth_bloc.dart';

enum AuthStatus { unknown, unauthenticated, codeSent, authenticated }

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.phone,
    this.devCode,
    this.busy = false,
    this.error,
  });

  final AuthStatus status;
  final AppUser? user;
  final String? phone;

  /// Dev-only OTP echoed by the backend, shown as a hint on the OTP screen.
  final String? devCode;
  final bool busy;
  final String? error;

  static const Object _sentinel = Object();

  AuthState copyWith({
    AuthStatus? status,
    Object? user = _sentinel,
    Object? phone = _sentinel,
    Object? devCode = _sentinel,
    bool? busy,
    Object? error = _sentinel,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user == _sentinel ? this.user : user as AppUser?,
      phone: phone == _sentinel ? this.phone : phone as String?,
      devCode: devCode == _sentinel ? this.devCode : devCode as String?,
      busy: busy ?? this.busy,
      error: error == _sentinel ? this.error : error as String?,
    );
  }

  @override
  List<Object?> get props => [status, user, phone, devCode, busy, error];
}
