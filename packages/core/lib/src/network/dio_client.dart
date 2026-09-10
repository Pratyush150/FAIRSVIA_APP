import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'auth_interceptor.dart';
import 'token_storage.dart';

/// Builds the app's Dio instances.
///
/// [refreshDio] is a bare client (no auth interceptor) used both to refresh
/// tokens and to replay retried requests. [authenticatedDio] carries the
/// [AuthInterceptor] and is what feature data sources use.
class DioClient {
  DioClient({required AppConfig config, required TokenStorage storage}) {
    final baseOptions = BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
    );

    refreshDio = Dio(baseOptions);
    _auth = AuthInterceptor(storage, refreshDio);
    authenticatedDio = Dio(baseOptions)..interceptors.add(_auth);
  }

  late final Dio refreshDio;
  late final Dio authenticatedDio;
  late final AuthInterceptor _auth;

  /// See [AuthInterceptor.sessionExpired].
  Stream<void> get sessionExpired => _auth.sessionExpired;
}
