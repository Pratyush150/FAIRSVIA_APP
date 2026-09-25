import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';

/// Earnings for a range (`GET /drivers/me/earnings`): the total, trip count,
/// online time, the last seven business days (the week chart) and the trips
/// that made up the range. Everything past `total`/`trips` is optional so an
/// older backend still parses.
class DriverEarnings {
  const DriverEarnings({
    required this.total,
    required this.trips,
    required this.range,
    this.onlineSeconds,
    this.cancellationFees = 0,
    this.days = const [],
    this.recentTrips = const [],
  });
  final double total;
  final int trips;
  final String range;

  /// Seconds online in the range; null when the server doesn't report it.
  final int? onlineSeconds;

  /// No-show / late-cancel compensation included in [total].
  final double cancellationFees;

  /// Oldest first, today last. Empty on an older backend.
  final List<EarningsDay> days;
  final List<EarnedTrip> recentTrips;

  factory DriverEarnings.fromJson(Map<String, dynamic> json) => DriverEarnings(
        total: (json['total'] as num?)?.toDouble() ?? 0,
        trips: (json['trips'] as num?)?.toInt() ?? 0,
        range: json['range'] as String? ?? 'today',
        onlineSeconds: (json['onlineSeconds'] as num?)?.toInt(),
        cancellationFees: (json['cancellationFees'] as num?)?.toDouble() ?? 0,
        days: (json['days'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EarningsDay.fromJson)
            .toList(),
        recentTrips: (json['recentTrips'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EarnedTrip.fromJson)
            .toList(),
      );
}

/// One business day of the earnings week.
class EarningsDay {
  const EarningsDay({
    required this.date,
    required this.total,
    required this.trips,
    this.onlineSeconds = 0,
  });

  /// Local calendar day, `YYYY-MM-DD` parsed to a date-only [DateTime].
  final DateTime date;
  final double total;
  final int trips;
  final int onlineSeconds;

  factory EarningsDay.fromJson(Map<String, dynamic> j) => EarningsDay(
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime(1970),
        total: (j['total'] as num?)?.toDouble() ?? 0,
        trips: (j['trips'] as num?)?.toInt() ?? 0,
        onlineSeconds: (j['onlineSeconds'] as num?)?.toInt() ?? 0,
      );
}

/// One completed trip on the earnings page: what the driver earned from it.
class EarnedTrip {
  const EarnedTrip({
    required this.id,
    required this.earned,
    this.completedAt,
    this.pickupAddr,
    this.dropoffAddr,
    this.distanceM,
    this.tip = 0,
    this.paymentMode = 'card',
  });

  final String id;
  final double earned;
  final DateTime? completedAt;
  final String? pickupAddr;
  final String? dropoffAddr;
  final int? distanceM;
  final double tip;
  final String paymentMode;

  factory EarnedTrip.fromJson(Map<String, dynamic> j) => EarnedTrip(
        id: j['id'] as String? ?? '',
        earned: (j['earned'] as num?)?.toDouble() ?? 0,
        completedAt: j['completedAt'] is String
            ? DateTime.tryParse(j['completedAt'] as String)?.toLocal()
            : null,
        pickupAddr: j['pickupAddr'] as String?,
        dropoffAddr: j['dropoffAddr'] as String?,
        distanceM: (j['distanceM'] as num?)?.toInt(),
        tip: (j['tip'] as num?)?.toDouble() ?? 0,
        paymentMode: j['paymentMode'] as String? ?? 'card',
      );
}

/// A "busy area" on the driver map: recent ride requests in a ~1 km cell.
class DemandCell {
  const DemandCell({
    required this.lat,
    required this.lng,
    required this.count,
    required this.intensity,
  });

  final double lat;
  final double lng;
  final int count;

  /// 0–1, relative to the busiest cell returned.
  final double intensity;

  factory DemandCell.fromJson(Map<String, dynamic> j) => DemandCell(
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lng: (j['lng'] as num?)?.toDouble() ?? 0,
        count: (j['count'] as num?)?.toInt() ?? 0,
        intensity: ((j['intensity'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0),
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
        currency: json['currency'] as String? ?? Market.current.currency,
        entries: (json['entries'] as List<dynamic>? ?? const [])
            .map((e) => LedgerEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A driver's Stripe Connect payout readiness (`GET /drivers/connect/status`).
class ConnectStatus {
  const ConnectStatus({
    required this.onboarded,
    required this.payoutsEnabled,
    required this.detailsSubmitted,
  });

  /// A connected account exists (onboarding at least started).
  final bool onboarded;

  /// Stripe will pay out to the driver's bank (KYC + bank complete).
  final bool payoutsEnabled;

  /// The driver finished the hosted onboarding form.
  final bool detailsSubmitted;

  factory ConnectStatus.fromJson(Map<String, dynamic> j) => ConnectStatus(
        onboarded: j['onboarded'] as bool? ?? false,
        payoutsEnabled: j['payoutsEnabled'] as bool? ?? false,
        detailsSubmitted: j['detailsSubmitted'] as bool? ?? false,
      );
}

/// The driver's own profile row (`GET /drivers/me`).
class DriverProfile {
  const DriverProfile({
    required this.status,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.plateNumber,
    required this.vehicleTier,
    required this.docsVerified,
    this.vehicleColor,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> j) => DriverProfile(
        status: j['status'] as String? ?? 'offline',
        vehicleMake: j['vehicleMake'] as String? ?? '',
        vehicleModel: j['vehicleModel'] as String? ?? '',
        vehicleColor: j['vehicleColor'] as String?,
        plateNumber: j['plateNumber'] as String? ?? '',
        vehicleTier: j['vehicleTier'] as String? ?? 'economy',
        docsVerified: j['docsVerified'] as bool? ?? false,
      );

  /// Server-side presence: 'online' | 'offline' | 'on_trip'.
  final String status;
  final String vehicleMake;
  final String vehicleModel;
  final String? vehicleColor;
  final String plateNumber;
  final String vehicleTier;
  final bool docsVerified;
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

  /// Own profile incl. the server's view of our presence.
  Future<DriverProfile> me() async {
    final res =
        await _guard(() => _dio.get<Map<String, dynamic>>('/drivers/me'));
    return DriverProfile.fromJson(res.data ?? const {});
  }

  Future<void> setStatus(String status) =>
      _guard(() => _dio.post('/drivers/status', data: {'status': status}));

  Future<void> arrived(String tripId) =>
      _guard(() => _dio.post('/trips/$tripId/arrived'));

  Future<void> start(String tripId, String otp) =>
      _guard(() => _dio.post('/trips/$tripId/start', data: {'otp': otp}));

  /// Completes the trip wherever the car is and returns the settlement
  /// receipt (fareFinal, driverPayout, paymentMode, breakdown ...). Away from
  /// the drop-off the server charges metered with the minimum-fare floor;
  /// [endEarly] + [reason] records an explicit early end.
  Future<Map<String, dynamic>> complete(
    String tripId, {
    bool endEarly = false,
    String? reason,
  }) async {
    final res = await _guard(
      () => _dio.post<Map<String, dynamic>>(
        '/trips/$tripId/complete',
        data: endEarly ? {'endEarly': true, 'reason': reason} : null,
      ),
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

  /// Start (or resume) Stripe Connect Express onboarding; returns the hosted
  /// onboarding URL to open in a browser.
  Future<String> connectOnboard() async {
    final res = await _guard(
      () => _dio.post<Map<String, dynamic>>('/drivers/connect/onboard'),
    );
    return res.data!['url'] as String;
  }

  /// Poll the driver's payout readiness (after returning from onboarding).
  Future<ConnectStatus> connectStatus() async {
    final res = await _guard(
      () => _dio.get<Map<String, dynamic>>('/drivers/connect/status'),
    );
    return ConnectStatus.fromJson(res.data!);
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

  /// Busy areas around ([lat], [lng]) from the last hour's ride requests.
  Future<List<DemandCell>> demand(double lat, double lng) async {
    final res = await _guard(
      () => _dio.get<Map<String, dynamic>>(
        '/drivers/me/demand',
        queryParameters: {'lat': lat, 'lng': lng},
      ),
    );
    return (res.data?['cells'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DemandCell.fromJson)
        .toList();
  }

  /// Driver-side cancel before the ride starts. [noShow] cancels as a rider
  /// no-show (only after the wait at the pickup) and returns the fee the
  /// rider was charged — the driver's compensation; 0 otherwise.
  Future<double> driverCancel(
    String tripId, {
    required String reason,
    bool noShow = false,
  }) async {
    final res = await _guard(
      () => _dio.post<Map<String, dynamic>>(
        '/trips/$tripId/driver-cancel',
        data: {'reason': reason, if (noShow) 'noShow': true},
      ),
    );
    return (res.data?['fee'] as num?)?.toDouble() ?? 0;
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
