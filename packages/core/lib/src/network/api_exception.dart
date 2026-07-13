import 'package:dio/dio.dart';

/// A normalized, UI-friendly error surfaced from the network layer.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// Map a Dio failure into a user-facing message (backend `message` field,
  /// or a connectivity hint).
  factory ApiException.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;
    String message = 'Something went wrong. Please try again.';
    if (body is Map && body['message'] != null) {
      final m = body['message'];
      message = m is List ? m.join(', ') : m.toString();
    } else if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      message = 'Cannot reach the server. Check your connection.';
    }
    return ApiException(message, statusCode: status);
  }

  @override
  String toString() => message;
}
