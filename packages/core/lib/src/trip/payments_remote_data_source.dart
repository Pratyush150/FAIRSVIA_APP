import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

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
    this.chargedAmount,
    this.breakdown,
  });

  final String tripId;

  /// The trip's fare (`fareFinal`, falling back to the estimate).
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

  /// The fare amount actually charged/collected on the payment record
  /// (`payment.amount`; tips are charged separately and live in [tip]).
  /// Null when no payment record exists yet.
  final double? chargedAmount;

  /// Itemised fare (base / distance / time / booking fee / surge / promo /
  /// tip). Null for trips settled before the backend recorded one.
  final FareBreakdown? breakdown;

  bool get isCash => method == 'cash';
  bool get isRefunded => refundedAmount > 0;

  /// What the rider ultimately paid: charged fare + tip, net of any refund.
  /// Never negative (a refund can't exceed the charge server-side, but guard).
  double get total {
    final net = (chargedAmount ?? fare) + tip - refundedAmount;
    return net < 0 ? 0 : net;
  }

  factory Receipt.fromJson(Map<String, dynamic> j) {
    final p = j['payment'] as Map<String, dynamic>?;
    return Receipt(
      tripId: j['tripId'] as String,
      fare: (j['fare'] as num?)?.toDouble() ?? 0,
      currency: j['currency'] as String? ?? 'USD',
      status: p?['status'] as String?,
      tip: (p?['tip'] as num?)?.toDouble() ?? 0,
      platformFee: (p?['platformFee'] as num?)?.toDouble(),
      driverPayout: (p?['driverPayout'] as num?)?.toDouble(),
      method: p?['method'] as String? ?? 'card',
      refundedAmount: (p?['refundedAmount'] as num?)?.toDouble() ?? 0,
      chargedAmount: (p?['amount'] as num?)?.toDouble(),
      breakdown: FareBreakdown.fromJsonOrNull(j['breakdown']),
    );
  }
}

/// The secrets a client PaymentSheet needs to save a card, plus the publishable
/// key. `isConfigured` is false when the backend is running the mock gateway
/// (no publishable key) — the UI then falls back to the mock add-card flow.
class StripeSetupIntent {
  const StripeSetupIntent({
    required this.publishableKey,
    this.setupIntentClientSecret,
    this.customerId,
    this.ephemeralKeySecret,
  });

  final String publishableKey;
  final String? setupIntentClientSecret;
  final String? customerId;
  final String? ephemeralKeySecret;

  /// True only when real Stripe is wired (publishable key + a client secret).
  bool get isConfigured =>
      publishableKey.isNotEmpty &&
      (setupIntentClientSecret?.isNotEmpty ?? false);

  factory StripeSetupIntent.fromJson(Map<String, dynamic> j) => StripeSetupIntent(
        publishableKey: j['publishableKey'] as String? ?? '',
        setupIntentClientSecret: j['setupIntentClientSecret'] as String?,
        customerId: j['customerId'] as String?,
        ephemeralKeySecret: j['ephemeralKeySecret'] as String?,
      );
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

  /// Begin saving a real card: returns the PaymentSheet secrets + publishable
  /// key. When the backend runs the mock gateway the publishable key is empty
  /// (`isConfigured` false) and the caller uses the mock add-card flow instead.
  /// Delete a saved card. The backend promotes another card to default when
  /// the removed one was the default.
  Future<void> removeMethod(String id) async {
    try {
      await _dio.delete<void>('/payments/methods/$id');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Make [id] the default card for future rides.
  Future<void> setDefaultMethod(String id) async {
    try {
      await _dio.patch<void>('/payments/methods/$id/default');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<StripeSetupIntent> createSetupIntent() async {
    try {
      final res =
          await _dio.post<Map<String, dynamic>>('/payments/setup-intent');
      return StripeSetupIntent.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Pull the customer's saved cards from Stripe into our list (called after the
  /// PaymentSheet saves a card). Returns the refreshed method list.
  Future<List<Map<String, dynamic>>> syncMethods() async {
    try {
      final res =
          await _dio.post<List<dynamic>>('/payments/methods/sync');
      return res.data!.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
