import 'package:dio/dio.dart';

/// A normalized, UI-friendly error surfaced from the network layer.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code, this.body});

  final String message;
  final int? statusCode;

  /// The backend's machine-readable error code (`code` in the JSON body, e.g.
  /// `PRICE_CHANGED`), when it sent one.
  final String? code;

  /// The decoded JSON error body, so callers can read contract-specific
  /// fields (a 409 PRICE_CHANGED carries `fare`, `surge`, `estimate`).
  final Map<String, dynamic>? body;

  /// Map a Dio failure into a user-facing message (backend `message` field,
  /// or a connectivity hint).
  factory ApiException.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final raw = e.response?.data;
    final body = raw is Map ? Map<String, dynamic>.from(raw) : null;
    String message = 'Something went wrong. Please try again.';
    if (body != null && body['message'] != null) {
      final m = body['message'];
      message = m is List ? m.join(', ') : m.toString();
    } else if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      message = 'Cannot reach the server. Check your connection.';
    }
    final code = body?['code'];
    return ApiException(
      message,
      statusCode: status,
      code: code is String ? code : null,
      body: body,
    );
  }

  @override
  String toString() => message;
}
