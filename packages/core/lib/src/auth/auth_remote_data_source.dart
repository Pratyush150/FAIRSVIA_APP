import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

/// Result of an OTP request. In dev the backend echoes [devCode] so the app
/// can prefill/display it without a real SMS.
class OtpRequestResult {
  const OtpRequestResult({required this.requestId, this.devCode});
  final String requestId;
  final String? devCode;
}

/// Thin HTTP client for the /auth and /users endpoints.
class AuthRemoteDataSource {
  AuthRemoteDataSource(this._dio);

  final Dio _dio;

  Future<OtpRequestResult> requestOtp(String phone) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/otp/request',
        data: {'phone': phone},
      );
      final data = res.data ?? const {};
      return OtpRequestResult(
        requestId: data['requestId'] as String? ?? '',
        devCode: data['devCode'] as String?,
      );
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<AuthSession> verifyOtp(String phone, String code) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/otp/verify',
        data: {'phone': phone, 'code': code},
      );
      return AuthSession.fromJson(res.data!);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  /// Revoke the refresh token server-side (`POST /auth/logout`). Callers
  /// wipe local tokens regardless of the outcome.
  Future<void> logout(String? refreshToken) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/auth/logout',
        data: {'refreshToken': ?refreshToken},
      );
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<AppUser> getMe() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/users/me');
      return AppUser.fromJson(res.data!);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    String message = 'Something went wrong. Please try again.';
    if (body is Map && body['message'] != null) {
      final m = body['message'];
      message = m is List ? m.join(', ') : m.toString();
    } else if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      message = 'Cannot reach the server. Check your connection.';
    }
    return ApiException(message, statusCode: status);
  }
}
