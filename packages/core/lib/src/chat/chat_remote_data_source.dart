import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

/// Loads/sends in-trip chat messages (`/trips/:id/messages`). Live delivery is
/// over the socket (`trip:message`); this REST source loads history and offers
/// a send fallback when the socket isn't connected.
class ChatRemoteDataSource {
  ChatRemoteDataSource(this._dio);
  final Dio _dio;

  Future<List<ChatMessage>> history(String tripId) async {
    try {
      final res =
          await _dio.get<List<dynamic>>('/trips/$tripId/messages');
      return (res.data ?? const [])
          .cast<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<ChatMessage> send(String tripId, String text) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trips/$tripId/messages',
        data: {'text': text},
      );
      return ChatMessage.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
