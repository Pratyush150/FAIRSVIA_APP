import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

/// Calls the backend Places proxy (which fronts Google Places).
class PlacesRemoteDataSource {
  PlacesRemoteDataSource(this._dio);

  final Dio _dio;

  /// Autocomplete [query]. With [near] (the rider's current position) the
  /// backend biases results around it and reports `distanceM` per prediction;
  /// when every prediction carries one the list is returned nearest-first
  /// (the provider's bias alone is soft).
  Future<List<PlacePrediction>> autocomplete(
    String query, {
    String? sessionToken,
    GeoPoint? near,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/places/autocomplete',
        queryParameters: {
          'q': query,
          'sessionToken': ?sessionToken,
          'lat': ?near?.lat,
          'lng': ?near?.lng,
        },
      );
      final predictions = (res.data?['predictions'] as List<dynamic>? ?? [])
          .map((e) => PlacePrediction.fromJson(e as Map<String, dynamic>))
          .toList();
      return PlacePrediction.sortedByDistance(predictions);
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

  /// Reverse-geocode raw coordinates (the rider's GPS) to a human address.
  Future<PlaceDetails> reverse(double lat, double lng) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/places/reverse',
        queryParameters: {'lat': lat, 'lng': lng},
      );
      return PlaceDetails.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
