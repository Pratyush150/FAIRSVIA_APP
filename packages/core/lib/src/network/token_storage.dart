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

/// Persists the JWT pair via the injected [KeyValueStore].
class TokenStorage {
  TokenStorage(this._storage);

  final KeyValueStore _storage;

  static const _accessKey = 'ubernav.access_token';
  static const _refreshKey = 'ubernav.refresh_token';

  Future<void> save(AuthTokens tokens) async {
    await _storage.write(_accessKey, tokens.accessToken);
    await _storage.write(_refreshKey, tokens.refreshToken);
  }

  Future<String?> readAccessToken() => _storage.read(_accessKey);

  Future<String?> readRefreshToken() => _storage.read(_refreshKey);

  Future<bool> hasSession() async =>
      (await readAccessToken())?.isNotEmpty ?? false;

  Future<void> clear() async {
    await _storage.delete(_accessKey);
    await _storage.delete(_refreshKey);
  }
}
