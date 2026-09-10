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

/// The user finished first-time profile setup or edited their profile later
/// (name/email); refresh the session user so the router advances from the
/// setup screen to home and the cached user stays current.
class AuthProfileCompleted extends AuthEvent {
  const AuthProfileCompleted(this.user);
  final AppUser user;

  @override
  List<Object?> get props => [user];
}

/// Log out and clear the stored session.
class AuthSignedOut extends AuthEvent {
  const AuthSignedOut();
}

/// The network layer could not refresh an expired access token and has
/// already cleared the stored tokens; drop to unauthenticated so the router
/// sends the user back to sign-in instead of leaving every call to 401.
class AuthSessionExpired extends AuthEvent {
  const AuthSessionExpired();
}
