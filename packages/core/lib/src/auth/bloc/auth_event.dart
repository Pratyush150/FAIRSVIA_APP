part of 'auth_bloc.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Fired once on app start to restore any existing session.
class AuthStarted extends AuthEvent {
  const AuthStarted();
}

/// User submitted their phone number; request an OTP.
class AuthOtpRequested extends AuthEvent {
  const AuthOtpRequested(this.phone);
  final String phone;

  @override
  List<Object?> get props => [phone];
}

/// User entered the OTP code; verify it.
class AuthOtpSubmitted extends AuthEvent {
  const AuthOtpSubmitted(this.code);
  final String code;

  @override
  List<Object?> get props => [code];
}

/// Return from the OTP screen to phone entry.
class AuthBackToPhone extends AuthEvent {
  const AuthBackToPhone();
}

/// Log out and clear the stored session.
class AuthSignedOut extends AuthEvent {
  const AuthSignedOut();
}
