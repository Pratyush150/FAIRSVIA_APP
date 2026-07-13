import 'package:equatable/equatable.dart';

import 'app_user.dart';
import 'auth_tokens.dart';

/// The result of a successful OTP verification: tokens + the authenticated user.
class AuthSession extends Equatable {
  const AuthSession({required this.tokens, required this.user});

  final AuthTokens tokens;
  final AppUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      tokens: AuthTokens.fromJson(json),
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  @override
  List<Object?> get props => [tokens, user];
}
