import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

/// Rider favourite-driver management (`/me/favorites`, `/drivers/:id/favorite`).
class FavoritesRemoteDataSource {
  FavoritesRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<FavoriteDriver>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>('/me/favorites');
      return (res.data ?? const [])
          .cast<Map<String, dynamic>>()
          .map(FavoriteDriver.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> add(String driverId) async {
    try {
      await _dio.post<Map<String, dynamic>>('/drivers/$driverId/favorite');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> remove(String driverId) async {
    try {
      await _dio.delete<Map<String, dynamic>>('/drivers/$driverId/favorite');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
