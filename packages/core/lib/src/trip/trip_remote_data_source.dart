import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

class TripRemoteDataSource {
  TripRemoteDataSource(this._dio);

  final Dio _dio;

  Future<TripEstimate> estimate(GeoPoint pickup, GeoPoint dropoff) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trips/estimate',
        data: {
          'pickupLat': pickup.lat,
          'pickupLng': pickup.lng,
          'dropoffLat': dropoff.lat,
          'dropoffLng': dropoff.lng,
        },
      );
      return TripEstimate.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Trip> create({
    required GeoPoint pickup,
    required GeoPoint dropoff,
    required String tier,
    String? pickupAddr,
    String? dropoffAddr,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trips',
        data: {
          'pickupLat': pickup.lat,
          'pickupLng': pickup.lng,
          'dropoffLat': dropoff.lat,
          'dropoffLng': dropoff.lng,
          'tier': tier,
          'pickupAddr': ?pickupAddr,
          'dropoffAddr': ?dropoffAddr,
        },
      );
      return Trip.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// The signed-in user's recent trips (rider or driver side), newest first.
  Future<List<Trip>> history() async {
    try {
      final res = await _dio.get<List<dynamic>>('/trips/history');
      return (res.data ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Trip.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Trip> getById(String id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/trips/$id');
      return Trip.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> cancel(String id, {String? reason}) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/trips/$id/cancel',
        data: {'reason': ?reason},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
