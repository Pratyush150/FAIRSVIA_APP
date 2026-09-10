import 'dart:async';

import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import 'token_storage.dart';

/// Attaches the access token to every request and, on a 401, transparently
/// refreshes the token pair once and retries the original request.
///
/// A single-flight lock ([_refreshing]) ensures concurrent 401s trigger only
/// one refresh call; the rest await its result.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage, this._refreshDio);

  final TokenStorage _storage;
  // Bare Dio (no interceptors) used only to hit /auth/refresh, avoiding recursion.
  final Dio _refreshDio;

  Completer<bool>? _refreshing;

  final _sessionExpired = StreamController<void>.broadcast();

  /// Fires after a 401 whose token refresh failed: the stored tokens have been
  /// cleared and the user must sign in again. [AuthBloc] listens and drops to
  /// unauthenticated so the router leaves the signed-in shell.
  Stream<void> get sessionExpired => _sessionExpired.stream;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final is401 = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra['__retried'] == true;
    final isRefreshCall =
        err.requestOptions.path.contains('/auth/refresh');

    if (!is401 || alreadyRetried || isRefreshCall) {
      return handler.next(err);
    }

    final refreshed = await _refreshTokens();
    if (!refreshed) {
      // Only a real session can expire: a 401 with no refresh token (e.g. an
      // unauthenticated call during sign-in) is just an error, not a sign-out.
      final hadSession = await _storage.hasSession();
      await _storage.clear();
      if (hadSession && !_sessionExpired.isClosed) _sessionExpired.add(null);
      return handler.next(err);
    }

    // Retry the original request once with the new access token.
    try {
      final newToken = await _storage.readAccessToken();
      final options = err.requestOptions
        ..extra['__retried'] = true
        ..headers['Authorization'] = 'Bearer $newToken';
      final response = await _refreshDio.fetch<dynamic>(options);
      return handler.resolve(response);
    } catch (_) {
      return handler.next(err);
    }
  }

  Future<bool> _refreshTokens() {
    // Coalesce concurrent refreshes.
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<bool>();
    _refreshing = completer;

    _doRefresh().then((ok) {
      _refreshing = null;
      completer.complete(ok);
    }).catchError((_) {
      _refreshing = null;
      completer.complete(false);
    });

    return completer.future;
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    final response = await _refreshDio.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    final data = response.data;
    if (data == null) return false;

    await _storage.save(AuthTokens.fromJson(data));
    return true;
  }
}
