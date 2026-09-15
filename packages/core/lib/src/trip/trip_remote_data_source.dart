import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

/// The `/trips/active` snapshot: the trip plus, when the server includes
/// them, the assigned driver and their approach route — the same shape as the
/// `trip:accepted` socket payload (`driver`, `vehicle`, `etaSec`,
/// `etaDistanceM`, `driverPolyline`). Lets the rider rebuild the driver card
/// after a cold start instead of showing "—" until the next socket event.
class ActiveTrip {
  const ActiveTrip({required this.trip, this.driver, this.driverPolyline});

  final Trip trip;

  /// Null when the server didn't send a `driver` object (older backends, or
  /// no driver assigned yet).
  final AssignedDriver? driver;
  final String? driverPolyline;

  factory ActiveTrip.fromJson(Map<String, dynamic> json) {
    final hasDriver = json['driver'] is Map;
    final polyline = json['driverPolyline'] as String?;
    return ActiveTrip(
      trip: Trip.fromJson(json),
      driver: hasDriver ? AssignedDriver.fromAcceptedEvent(json) : null,
      driverPolyline: (polyline == null || polyline.isEmpty) ? null : polyline,
    );
  }
}

class TripRemoteDataSource {
  TripRemoteDataSource(this._dio);

  final Dio _dio;

  Future<TripEstimate> estimate(
    GeoPoint pickup,
    GeoPoint dropoff, {
    List<TripStop> stops = const [],
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trips/estimate',
        data: {
          'pickupLat': pickup.lat,
          'pickupLng': pickup.lng,
          'dropoffLat': dropoff.lat,
          'dropoffLng': dropoff.lng,
          if (stops.isNotEmpty) 'stops': stops.map((s) => s.toJson()).toList(),
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
    String? pickupNote,
    String? promoCode,
    String? paymentMode,
    String? paymentMethodId,
    DateTime? scheduledAt,
    List<TripStop> stops = const [],
    double? quotedFare,
    double? quotedSurge,
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
          'pickupNote': ?pickupNote,
          'promoCode': ?promoCode,
          'paymentMode': ?paymentMode,
          'paymentMethodId': ?paymentMethodId,
          'scheduledAt': ?scheduledAt?.toUtc().toIso8601String(),
          if (stops.isNotEmpty) 'stops': stops.map((s) => s.toJson()).toList(),
          // Price lock: the fare/surge the rider saw on the sheet. A move
          // beyond the server's tolerance is refused with 409 PRICE_CHANGED
          // (see ApiException.code/body) so the rider re-confirms.
          'quotedFare': ?quotedFare,
          'quotedSurge': ?quotedSurge,
        },
      );
      return Trip.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Prices a promo code against a fare subtotal. Returns the quote on success;
  /// throws [ApiException] whose message is the rider-facing rejection reason.
  Future<PromoQuote> quotePromo(String code, num subtotal) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/promos/quote',
        data: {'code': code, 'subtotal': subtotal},
      );
      return PromoQuote.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// The rider's upcoming scheduled rides, soonest first.
  Future<List<Trip>> scheduled() async {
    try {
      final res = await _dio.get<List<dynamic>>('/trips/scheduled');
      return (res.data ?? const [])
          .cast<Map<String, dynamic>>()
          .map(Trip.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// The caller's in-flight trip, or null when there isn't one. Used to
  /// restore the live-tracking screen after the app is killed mid-ride.
  Future<Trip?> active() async => (await activeDetails())?.trip;

  /// Like [active], but keeps the driver/approach-route keys when present.
  Future<ActiveTrip?> activeDetails() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/trips/active');
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      return ActiveTrip.fromJson(data);
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

  /// Cancels the trip and returns the cancellation fee charged (0 when none —
  /// a fee only applies once a driver has committed).
  Future<double> cancel(String id, {String? reason}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/trips/$id/cancel',
        data: {'reason': ?reason},
      );
      return (res.data?['fee'] as num?)?.toDouble() ?? 0;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
