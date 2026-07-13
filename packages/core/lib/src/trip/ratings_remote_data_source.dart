import 'package:dio/dio.dart';

import '../network/api_exception.dart';

/// Two-way ratings (`/trips/:id/rating`). Either party rates the other after a
/// completed trip; re-submitting updates the existing rating.
class RatingsRemoteDataSource {
  RatingsRemoteDataSource(this._dio);
  final Dio _dio;

  Future<void> rate(
    String tripId, {
    required int stars,
    String? comment,
    List<String>? tags,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/trips/$tripId/rating',
        data: {
          'stars': stars,
          'comment': ?comment,
          'tags': ?tags,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// The rating this user already gave for the trip, or null.
  Future<int?> myRating(String tripId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/trips/$tripId/rating');
      return (res.data?['stars'] as num?)?.toInt();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
