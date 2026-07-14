import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

/// In-app notification inbox (`/me/notifications`).
class InboxRemoteDataSource {
  InboxRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<InboxNotification>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>('/me/notifications');
      return (res.data ?? const [])
          .cast<Map<String, dynamic>>()
          .map(InboxNotification.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<int> unreadCount() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/me/notifications/unread-count',
      );
      return (res.data?['unread'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _dio.post<Map<String, dynamic>>('/me/notifications/$id/read');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> markAllRead() async {
    try {
      await _dio.post<Map<String, dynamic>>('/me/notifications/read-all');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
