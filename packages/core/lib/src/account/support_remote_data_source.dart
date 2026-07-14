import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

/// User-facing support tickets (`/support/tickets`). Riders and drivers both
/// use this; the admin app talks to `/admin/support/tickets` separately.
class SupportRemoteDataSource {
  SupportRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<SupportTicket>> listMine() async {
    try {
      final res = await _dio.get<List<dynamic>>('/support/tickets');
      return (res.data ?? const [])
          .cast<Map<String, dynamic>>()
          .map(SupportTicket.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<SupportTicket> thread(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/support/tickets/$id');
      return SupportTicket.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<SupportTicket> create({
    required String subject,
    required String message,
    String? category,
    String? tripId,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/support/tickets',
        data: {
          'subject': subject,
          'message': message,
          'category': ?category,
          'tripId': ?tripId,
        },
      );
      return SupportTicket.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Appends a reply and returns the refreshed thread.
  Future<SupportTicket> reply(String id, String body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/support/tickets/$id/messages',
        data: {'body': body},
      );
      return SupportTicket.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
