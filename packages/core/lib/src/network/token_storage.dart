import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_models/shared_models.dart';

/// Minimal key/value contract so token storage can swap backends per platform.
abstract class KeyValueStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

/// Mobile/desktop: OS-backed secure storage (Keychain / Keystore).
class SecureKeyValueStore implements KeyValueStore {
  SecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Persists the signed-in session — the JWT pair, plus the last user the
/// server confirmed — via the injected [KeyValueStore].
class TokenStorage {
  TokenStorage(this._storage);

  final KeyValueStore _storage;

  static const _accessKey = 'ubernav.access_token';
  static const _refreshKey = 'ubernav.refresh_token';
  static const _userKey = 'ubernav.session_user';

  Future<void> save(AuthTokens tokens) async {
    await _storage.write(_accessKey, tokens.accessToken);
    await _storage.write(_refreshKey, tokens.refreshToken);
  }

  Future<String?> readAccessToken() => _storage.read(_accessKey);

  Future<String?> readRefreshToken() => _storage.read(_refreshKey);

  Future<bool> hasSession() async =>
      (await readAccessToken())?.isNotEmpty ?? false;

  /// Remember the signed-in user alongside their tokens, so a cold start with
  /// no usable connection can restore the session instead of bouncing to the
  /// phone screen. Best effort: failing to cache must never fail a sign-in.
  Future<void> cacheUser(AppUser user) async {
    try {
      await _storage.write(_userKey, jsonEncode(user.toJson()));
    } catch (_) {
      // Non-fatal — the next successful /users/me will cache again.
    }
  }

  /// The last user the server confirmed, or null when none is stored (or the
  /// stored copy can no longer be read, e.g. after a model change).
  Future<AppUser?> readCachedUser() async {
    try {
      final raw = await _storage.read(_userKey);
      if (raw == null || raw.isEmpty) return null;
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(_accessKey);
    await _storage.delete(_refreshKey);
    await _storage.delete(_userKey);
  }
}
