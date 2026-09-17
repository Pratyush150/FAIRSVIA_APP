import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import 'token_storage.dart';

/// What came back from an attempt to refresh the token pair.
///
/// The distinction between the two failures is the whole point: only the
/// server saying "this refresh token is no good" means the session is over.
/// A refresh that never reached the server says nothing about the session, and
/// treating it as expiry is what signed riders and drivers out every time they
/// changed network or reopened the app on a weak signal.
enum RefreshOutcome {
  /// A new pair was issued and stored.
  refreshed,

  /// The server answered, and the answer was no (401/403). Session is over.
  rejected,

  /// The server never gave a verdict — offline, timeout, DNS, 5xx, proxy.
  /// The stored tokens are left exactly as they are.
  unreachable,
}

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

  Completer<RefreshOutcome>? _refreshing;

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

    final outcome = await _refreshTokens();
    if (outcome == RefreshOutcome.unreachable) {
      // We could not ask. Keep the tokens and let the caller see a plain
      // network error: the next request on a working connection refreshes
      // normally. Signing out here is how switching from WiFi to cellular
      // mid-session logged people out.
      return handler.next(err);
    }
    if (outcome == RefreshOutcome.rejected) {
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

  /// A currently valid access token for out-of-band callers (the realtime
  /// socket handshake): refreshes first when the stored token is missing,
  /// unparseable, expired, or within [_expirySlack] of expiring. Returns null
  /// when no session can be established (refresh failed / signed out).
  Future<String?> freshAccessToken() async {
    final current = await _storage.readAccessToken();
    if (current != null && current.isNotEmpty) {
      final exp = jwtExpiry(current);
      if (exp != null && exp.isAfter(DateTime.now().add(_expirySlack))) {
        return current;
      }
    }
    final outcome = await _refreshTokens();
    if (outcome != RefreshOutcome.refreshed) return null;
    return _storage.readAccessToken();
  }

  static const _expirySlack = Duration(seconds: 60);

  /// `sub` claim (user id) of a JWT, or null if it can't be read.
  static String? jwtSubject(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final sub = (jsonDecode(payload) as Map<String, dynamic>)['sub'];
      return sub is String ? sub : null;
    } catch (_) {
      return null;
    }
  }

  /// `exp` claim of a JWT as a DateTime, or null if it can't be read.
  static DateTime? jwtExpiry(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final exp = (jsonDecode(payload) as Map<String, dynamic>)['exp'];
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    } catch (_) {
      return null;
    }
  }

  Future<RefreshOutcome> _refreshTokens() {
    // Coalesce concurrent refreshes.
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<RefreshOutcome>();
    _refreshing = completer;

    _doRefresh().then((outcome) {
      _refreshing = null;
      completer.complete(outcome);
    }).catchError((Object _) {
      _refreshing = null;
      // An unexpected throw is not the server telling us the session is dead.
      completer.complete(RefreshOutcome.unreachable);
    });

    return completer.future;
  }

  Future<RefreshOutcome> _doRefresh() async {
    final refreshToken = await _storage.readRefreshToken();
    // Nothing to refresh with: there is no session to keep alive.
    if (refreshToken == null || refreshToken.isEmpty) {
      return RefreshOutcome.rejected;
    }

    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data;
      // A 2xx with no body is a broken gateway, not a rejected session.
      if (data == null) return RefreshOutcome.unreachable;
      await _storage.save(AuthTokens.fromJson(data));
      return RefreshOutcome.refreshed;
    } on DioException catch (e) {
      return _isRejection(e)
          ? RefreshOutcome.rejected
          : RefreshOutcome.unreachable;
    } catch (_) {
      // Malformed body, storage failure — nothing that proves expiry.
      return RefreshOutcome.unreachable;
    }
  }

  /// True only when the server itself refused the refresh token. Everything
  /// else — no connection, timeout, 5xx, a captive-portal redirect — leaves
  /// the session intact.
  static bool _isRejection(DioException e) {
    final status = e.response?.statusCode;
    return status == 401 || status == 403;
  }
}
