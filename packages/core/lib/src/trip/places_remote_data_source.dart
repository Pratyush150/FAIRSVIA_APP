import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

/// Calls the backend Places proxy (which fronts Google Places).
class PlacesRemoteDataSource {
  PlacesRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<PlacePrediction>> autocomplete(
    String query, {
    String? sessionToken,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/places/autocomplete',
        queryParameters: {
          'q': query,
          'sessionToken': ?sessionToken,
        },
      );
      final predictions = (res.data?['predictions'] as List<dynamic>? ?? [])
          .map((e) => PlacePrediction.fromJson(e as Map<String, dynamic>))
          .toList();
      return predictions;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<PlaceDetails> details(String placeId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/places/details',
        queryParameters: {'placeId': placeId},
      );
      return PlaceDetails.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
