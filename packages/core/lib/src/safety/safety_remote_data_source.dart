import 'package:dio/dio.dart';

import '../network/api_exception.dart';

/// Calls the safety toolkit (`POST /trips/:id/sos`).
class SafetyRemoteDataSource {
  SafetyRemoteDataSource(this._dio);
  final Dio _dio;

  /// Raise an SOS for a trip. Optionally attaches the rider's coordinates.
  /// Returns a shareable summary from the backend.
  Future<Map<String, dynamic>> raiseSos(
    String tripId, {
    double? lat,
    double? lng,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trips/$tripId/sos',
        data: {'lat': ?lat, 'lng': ?lng},
      );
      return res.data ?? const {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
