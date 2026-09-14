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
}
