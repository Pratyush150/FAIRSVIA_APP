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

  /// On-demand road route between two points, for **live re-routing** when the
  /// driver leaves the planned path. Returns the fresh encoded polyline, or null
  /// when unavailable (the caller keeps the existing line rather than clearing
  /// it). Best-effort — never throws, so a transient failure can't break the map.
  Future<String?> route({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/places/route',
        queryParameters: {
          'fromLat': fromLat,
          'fromLng': fromLng,
          'toLat': toLat,
          'toLng': toLng,
        },
      );
      final poly = res.data?['polyline'] as String?;
      return (poly != null && poly.isNotEmpty) ? poly : null;
    } catch (_) {
      return null;
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
