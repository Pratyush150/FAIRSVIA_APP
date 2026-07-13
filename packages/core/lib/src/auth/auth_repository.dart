import 'package:shared_models/shared_models.dart';

import '../network/token_storage.dart';
import 'auth_remote_data_source.dart';

/// Coordinates the auth data source with secure token storage.
class AuthRepository {
  AuthRepository(this._remote, this._storage);

  final AuthRemoteDataSource _remote;
  final TokenStorage _storage;

  /// Request an OTP; returns the dev code when the backend is in dev mode.
  Future<String?> requestOtp(String phone) async {
    final result = await _remote.requestOtp(phone);
    return result.devCode;
  }

  /// Verify an OTP, persist the tokens, and return the authenticated user.
  Future<AppUser> verifyOtp(String phone, String code) async {
    final session = await _remote.verifyOtp(phone, code);
    await _storage.save(session.tokens);
    return session.user;
  }

  /// Restore the session on app start. Returns null if not logged in or the
  /// stored session is no longer valid.
  Future<AppUser?> restoreSession() async {
    if (!await _storage.hasSession()) return null;
    try {
      return await _remote.getMe();
    } catch (_) {
      await _storage.clear();
      return null;
    }
  }

  Future<void> signOut() => _storage.clear();
}
