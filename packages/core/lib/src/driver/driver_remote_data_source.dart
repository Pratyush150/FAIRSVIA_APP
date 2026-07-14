import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

class DriverEarnings {
  const DriverEarnings({required this.total, required this.trips, required this.range});
  final double total;
  final int trips;
  final String range;

  factory DriverEarnings.fromJson(Map<String, dynamic> json) => DriverEarnings(
        total: (json['total'] as num?)?.toDouble() ?? 0,
        trips: (json['trips'] as num?)?.toInt() ?? 0,
        range: json['range'] as String? ?? 'today',
      );
}

/// REST calls for the driver flow (status, onboarding, trip lifecycle, earnings).
class DriverRemoteDataSource {
  DriverRemoteDataSource(this._dio);

  final Dio _dio;

  Future<void> onboarding({
    required String vehicleMake,
    required String vehicleModel,
    required String plateNumber,
    required String vehicleTier,
    String? vehicleColor,
    String? licenseNo,
  }) async {
    await _guard(() => _dio.post<Map<String, dynamic>>('/drivers/onboarding', data: {
          'vehicleMake': vehicleMake,
          'vehicleModel': vehicleModel,
          'plateNumber': plateNumber,
          'vehicleTier': vehicleTier,
          'vehicleColor': ?vehicleColor,
          'licenseNo': ?licenseNo,
        }));
  }

  Future<void> setStatus(String status) =>
      _guard(() => _dio.post('/drivers/status', data: {'status': status}));

  Future<void> arrived(String tripId) =>
      _guard(() => _dio.post('/trips/$tripId/arrived'));

  Future<void> start(String tripId, String otp) =>
      _guard(() => _dio.post('/trips/$tripId/start', data: {'otp': otp}));

  /// Completes the trip and returns the settlement receipt (fareFinal,
  /// driverPayout, paymentMode, ...).
  Future<Map<String, dynamic>> complete(String tripId) async {
    final res = await _guard(
      () => _dio.post<Map<String, dynamic>>('/trips/$tripId/complete'),
    );
    return res.data ?? const {};
  }

  Future<Trip> getTrip(String tripId) async {
    final res = await _guard(
      () => _dio.get<Map<String, dynamic>>('/trips/$tripId'),
    );
    return Trip.fromJson(res.data!);
  }

  Future<DriverEarnings> earnings({String range = 'today'}) async {
    final res = await _guard(
      () => _dio.get<Map<String, dynamic>>(
        '/drivers/me/earnings',
        queryParameters: {'range': range},
      ),
    );
    return DriverEarnings.fromJson(res.data!);
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
