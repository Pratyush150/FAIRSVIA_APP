import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
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
    await _storage.cacheUser(session.user);
    return session.user;
  }

  /// Restore the session on app start.
  ///
  /// Only the server actively rejecting us (401/403, after the interceptor has
  /// already tried to refresh) means the session is over. Anything else is the
  /// network, and the tokens are kept: reopening the app on a weak signal, in
  /// a lift, or mid-handover between WiFi and cellular used to clear them and
  /// dump the user back on the phone-number screen with a live ride running.
  /// In that case we fall back to the last user the server confirmed, so the
  /// app opens signed in and the first successful call corrects anything stale.
  Future<AppUser?> restoreSession() async {
    if (!await _storage.hasSession()) return null;
    try {
      final user = await _remote.getMe();
      await _storage.cacheUser(user);
      return user;
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        await _storage.clear();
        return null;
      }
      return _storage.readCachedUser();
    } catch (_) {
      return _storage.readCachedUser();
    }
  }

  /// Revoke the session on the server (best effort — the device may be
  /// offline, and a local sign-out must never hang on the network), then
  /// always wipe the local tokens.
  Future<void> signOut() async {
    try {
      final refresh = await _storage.readRefreshToken();
      await _remote.logout(refresh).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Tokens are cleared below either way; the server's refresh token
      // simply expires on its own.
    }
    await _storage.clear();
  }
}
