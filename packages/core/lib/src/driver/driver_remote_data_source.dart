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

/// A single movement in the driver's payout balance.
class LedgerEntry {
  const LedgerEntry({
    required this.type,
    required this.amount,
    this.note,
    this.createdAt,
  });

  final String type; // earning|tip|commission|withdrawal|adjustment
  final double amount; // signed
  final String? note;
  final DateTime? createdAt;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        type: json['type'] as String? ?? 'adjustment',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        note: json['note'] as String?,
        createdAt: json['createdAt'] is String
            ? DateTime.tryParse(json['createdAt'] as String)?.toLocal()
            : null,
      );
}

/// The driver's payout balance plus recent ledger movements.
class PayoutBalance {
  const PayoutBalance({
    required this.balance,
    required this.currency,
    required this.entries,
  });

  final double balance;
  final String currency;
  final List<LedgerEntry> entries;

  factory PayoutBalance.fromJson(Map<String, dynamic> json) => PayoutBalance(
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'USD',
        entries: (json['entries'] as List<dynamic>? ?? const [])
            .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
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

  /// The driver's current active trip, or null. Used to restore the live trip
  /// screen after the app is killed and reopened mid-trip. When there's no
  /// active trip the server replies 200 with an empty body, so treat anything
  /// that isn't a non-empty JSON object as "no trip".
  Future<Trip?> getActiveTrip() async {
    final res = await _guard(() => _dio.get<dynamic>('/trips/active'));
    final data = res.data;
    if (data is Map && data.isNotEmpty) {
      return Trip.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
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

  /// Current payout balance + recent ledger movements.
  Future<PayoutBalance> balance() async {
    final res = await _guard(
      () => _dio.get<Map<String, dynamic>>('/drivers/balance'),
    );
    return PayoutBalance.fromJson(res.data!);
  }

  /// Withdraw [amount] of available balance; returns the new balance.
  Future<PayoutBalance> withdraw(double amount) async {
    await _guard(
      () => _dio.post<Map<String, dynamic>>(
        '/drivers/balance/withdraw',
        data: {'amount': amount},
      ),
    );
    return balance();
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
