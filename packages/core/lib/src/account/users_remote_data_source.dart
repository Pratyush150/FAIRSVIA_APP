import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

/// HTTP client for the authenticated user's profile and saved places
/// (`/users/me` and `/users/me/places`).
class UsersRemoteDataSource {
  UsersRemoteDataSource(this._dio);

  final Dio _dio;

  Future<AppUser> getMe() => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/users/me');
        return AppUser.fromJson(res.data!);
      });

  Future<AppUser> updateMe({String? fullName, String? email}) =>
      _guard(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          '/users/me',
          data: {
            'fullName': ?fullName,
            'email': ?email,
          },
        );
        return AppUser.fromJson(res.data!);
      });

  Future<List<SavedPlace>> listPlaces() => _guard(() async {
        final res = await _dio.get<List<dynamic>>('/users/me/places');
        return (res.data ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SavedPlace.fromJson)
            .toList();
      });

  Future<SavedPlace> addPlace({
    required String label,
    required double lat,
    required double lng,
    String? address,
  }) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/users/me/places',
          data: {
            'label': label,
            'lat': lat,
            'lng': lng,
            'address': ?address,
          },
        );
        return SavedPlace.fromJson(res.data!);
      });

  Future<SavedPlace> updatePlace(
    String id, {
    String? label,
    double? lat,
    double? lng,
    String? address,
  }) =>
      _guard(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          '/users/me/places/$id',
          data: {
            'label': ?label,
            'lat': ?lat,
            'lng': ?lng,
            'address': ?address,
          },
        );
        return SavedPlace.fromJson(res.data!);
      });

  /// Permanently deletes the signed-in account. The server refuses (409) while
  /// a ride is in progress or a driver still has a balance, with a message
  /// meant for the user.
  Future<void> deleteMe() =>
      _guard(() => _dio.delete<Map<String, dynamic>>('/users/me'));

  Future<void> deletePlace(String id) =>
      _guard(() => _dio.delete<Map<String, dynamic>>('/users/me/places/$id'));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
