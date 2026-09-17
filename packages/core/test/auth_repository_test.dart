import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockAuthRemote extends Mock implements AuthRemoteDataSource {}

class _MemoryStore implements KeyValueStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

void main() {
  late MockAuthRemote remote;
  late TokenStorage storage;
  late AuthRepository repo;

  setUp(() async {
    remote = MockAuthRemote();
    storage = TokenStorage(_MemoryStore());
    repo = AuthRepository(remote, storage);
    await storage.save(
      const AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
  });

  group('signOut', () {
    test('revokes the refresh token on the server, then clears locally',
        () async {
      when(() => remote.logout(any())).thenAnswer((_) async {});
      await repo.signOut();
      verify(() => remote.logout('refresh')).called(1);
      expect(await storage.hasSession(), isFalse);
    });

    test('still clears locally when the server call fails', () async {
      when(() => remote.logout(any()))
          .thenThrow(const ApiException('offline', statusCode: null));
      await repo.signOut();
      expect(await storage.hasSession(), isFalse);
    });
  });

  /// Reopening the app must not sign anyone out just because the first call
  /// out of the gate didn't land. Only the server rejecting us does that.
  group('restoreSession', () {
    const me = AppUser(id: 'u1', phone: '+15551234567', role: 'rider', fullName: 'Ada');

    test('returns the server copy and remembers it for next time', () async {
      when(() => remote.getMe()).thenAnswer((_) async => me);
      expect(await repo.restoreSession(), me);
      expect(await storage.readCachedUser(), me);
    });

    test('keeps the session and falls back to the cached user when offline',
        () async {
      when(() => remote.getMe()).thenAnswer((_) async => me);
      await repo.restoreSession(); // prime the cache while online

      when(() => remote.getMe()).thenThrow(
        const ApiException('Cannot reach the server. Check your connection.'),
      );
      expect(await repo.restoreSession(), me);
      expect(await storage.hasSession(), isTrue,
          reason: 'a dead network is not an expired session');
    });

    test('keeps the session on a server error (5xx)', () async {
      when(() => remote.getMe()).thenAnswer((_) async => me);
      await repo.restoreSession();

      when(() => remote.getMe())
          .thenThrow(const ApiException('boom', statusCode: 500));
      expect(await repo.restoreSession(), me);
      expect(await storage.hasSession(), isTrue);
    });

    test('signs out on a 401 — the session really is gone', () async {
      when(() => remote.getMe()).thenAnswer((_) async => me);
      await repo.restoreSession();

      when(() => remote.getMe())
          .thenThrow(const ApiException('nope', statusCode: 401));
      expect(await repo.restoreSession(), isNull);
      expect(await storage.hasSession(), isFalse);
      expect(await storage.readCachedUser(), isNull,
          reason: 'the cached user goes with the tokens');
    });

    test('offline with nothing cached yet returns null rather than a guess',
        () async {
      when(() => remote.getMe())
          .thenThrow(const ApiException('offline'));
      expect(await repo.restoreSession(), isNull);
      // Tokens are still kept: the next launch with signal can recover.
      expect(await storage.hasSession(), isTrue);
    });

    test('no stored session at all is simply not signed in', () async {
      await storage.clear();
      expect(await repo.restoreSession(), isNull);
      verifyNever(() => remote.getMe());
    });
  });
}
