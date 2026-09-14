import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

class _MemoryStore implements KeyValueStore {
  final map = <String, String>{};
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> delete(String key) async => map.remove(key);
}

/// Answers every request with the same status; records the paths it saw.
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);
  final int status;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      '{"message":"nope"}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}


/// Unsigned JWT with the given `exp` (seconds since epoch) — the interceptor
/// only reads the payload, it never verifies signatures.
String _jwt(int exp) {
  String enc(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${enc({'alg': 'HS256'})}.${enc({'sub': 'u1', 'exp': exp})}.sig';
}

void main() {
  late _MemoryStore store;
  late TokenStorage storage;
  late Dio refreshDio;
  late Dio dio;
  late AuthInterceptor interceptor;
  late _StatusAdapter adapter;

  setUp(() {
    store = _MemoryStore();
    storage = TokenStorage(store);
    adapter = _StatusAdapter(401);
    refreshDio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = adapter;
    interceptor = AuthInterceptor(storage, refreshDio);
    dio = Dio(BaseOptions(baseUrl: 'http://x'))
      ..httpClientAdapter = adapter
      ..interceptors.add(interceptor);
  });

  test('a 401 whose refresh fails clears tokens and signals sessionExpired',
      () async {
    await storage.save(
      const AuthTokens(accessToken: 'old', refreshToken: 'r1'),
    );
    final expired = Completer<void>();
    interceptor.sessionExpired.listen((_) => expired.complete());

    await expectLater(dio.get<dynamic>('/me'), throwsA(isA<DioException>()));

    await expired.future.timeout(const Duration(seconds: 2));
    expect(adapter.paths, ['/me', '/auth/refresh']);
    expect(await storage.hasSession(), isFalse);
  });

  test('a 401 with no stored session is just an error, not an expiry',
      () async {
    var fired = 0;
    interceptor.sessionExpired.listen((_) => fired++);

    await expectLater(dio.get<dynamic>('/me'), throwsA(isA<DioException>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(fired, 0);
    // No refresh token, so no refresh call was even attempted.
    expect(adapter.paths, ['/me']);
  });

  test('freshAccessToken returns a token that is not near expiry as-is',
      () async {
    final far = DateTime.now().add(const Duration(minutes: 10));
    final token = _jwt(far.millisecondsSinceEpoch ~/ 1000);
    await storage.save(AuthTokens(accessToken: token, refreshToken: 'r1'));
    expect(await interceptor.freshAccessToken(), token);
    expect(adapter.paths, isEmpty, reason: 'no refresh call needed');
  });

  test('freshAccessToken refreshes an expired token and returns null when '
      'the refresh is rejected', () async {
    final past = DateTime.now().subtract(const Duration(minutes: 1));
    await storage.save(
      AuthTokens(
        accessToken: _jwt(past.millisecondsSinceEpoch ~/ 1000),
        refreshToken: 'r1',
      ),
    );
    expect(await interceptor.freshAccessToken(), isNull);
    expect(adapter.paths, ['/auth/refresh']);
  });

  test('jwtExpiry reads exp and tolerates garbage', () {
    final exp = DateTime.now().add(const Duration(hours: 1));
    final secs = exp.millisecondsSinceEpoch ~/ 1000;
    expect(AuthInterceptor.jwtExpiry(_jwt(secs))?.millisecondsSinceEpoch,
        secs * 1000);
    expect(AuthInterceptor.jwtExpiry('not-a-jwt'), isNull);
    expect(AuthInterceptor.jwtExpiry('a.b.c'), isNull);
  });
}
