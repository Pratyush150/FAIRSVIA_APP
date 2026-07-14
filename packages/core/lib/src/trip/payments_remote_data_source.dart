import 'package:dio/dio.dart';

import '../network/api_exception.dart';

/// A fare/payment receipt for a trip (`GET /payments/:id/receipt`).
class Receipt {
  const Receipt({
    required this.tripId,
    required this.fare,
    required this.currency,
    this.status,
    this.tip = 0,
    this.platformFee,
    this.driverPayout,
    this.method = 'card',
    this.refundedAmount = 0,
  });

  final String tripId;
  final double fare;
  final String currency;
  final String? status;
  final double tip;
  final double? platformFee;
  final double? driverPayout;

  /// How the ride settled: `card` or `cash`.
  final String method;

  /// Amount refunded to the rider (0 when none).
  final double refundedAmount;

  bool get isCash => method == 'cash';
  bool get isRefunded => refundedAmount > 0;

  factory Receipt.fromJson(Map<String, dynamic> j) {
    final p = j['payment'] as Map<String, dynamic>?;
    return Receipt(
      tripId: j['tripId'] as String,
      fare: (j['fare'] as num?)?.toDouble() ?? 0,
      currency: j['currency'] as String? ?? 'INR',
      status: p?['status'] as String?,
      tip: (p?['tip'] as num?)?.toDouble() ?? 0,
      platformFee: (p?['platformFee'] as num?)?.toDouble(),
      driverPayout: (p?['driverPayout'] as num?)?.toDouble(),
      method: p?['method'] as String? ?? 'card',
      refundedAmount: (p?['refundedAmount'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Payment methods + tips + receipts (`/payments/...`).
class PaymentsRemoteDataSource {
  PaymentsRemoteDataSource(this._dio);
  final Dio _dio;

  Future<Receipt> receipt(String tripId) async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('/payments/$tripId/receipt');
      return Receipt.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Tip the driver (added 100% to their payout). Returns the new tip total.
  Future<double> tip(String tripId, double amount) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/payments/$tripId/tip',
        data: {'amount': amount},
      );
      return (res.data?['tip'] as num?)?.toDouble() ?? amount;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<List<Map<String, dynamic>>> methods() async {
    try {
      final res = await _dio.get<List<dynamic>>('/payments/methods');
      return res.data!.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> addMethod({String? brand, String? last4, String? externalId}) async {
    try {
      await _dio.post<Map<String, dynamic>>('/payments/methods', data: {
        'brand': ?brand,
        'last4': ?last4,
        'externalId': ?externalId,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
