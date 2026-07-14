import 'package:equatable/equatable.dart';

import 'geo_point.dart';
import 'trip_stop.dart';

enum TripStatus {
  scheduled,
  requested,
  matching,
  accepted,
  arrived,
  inProgress,
  completed,
  cancelled,
  noDrivers,
  paymentFailed,
  expired,
  unknown;

  static TripStatus fromString(String? value) {
    switch (value) {
      case 'scheduled':
        return TripStatus.scheduled;
      case 'requested':
        return TripStatus.requested;
      case 'matching':
        return TripStatus.matching;
      case 'accepted':
        return TripStatus.accepted;
      case 'arrived':
        return TripStatus.arrived;
      case 'in_progress':
        return TripStatus.inProgress;
      case 'completed':
        return TripStatus.completed;
      case 'cancelled':
        return TripStatus.cancelled;
      case 'no_drivers':
        return TripStatus.noDrivers;
      case 'payment_failed':
        return TripStatus.paymentFailed;
      case 'expired':
        return TripStatus.expired;
      default:
        return TripStatus.unknown;
    }
  }

  bool get isActive =>
      this == TripStatus.requested ||
      this == TripStatus.matching ||
      this == TripStatus.accepted ||
      this == TripStatus.arrived ||
      this == TripStatus.inProgress;
}

/// A trip endpoint: coordinates plus an optional human-readable address.
class TripEndpoint extends Equatable {
  const TripEndpoint({required this.point, this.address});

  final GeoPoint point;
  final String? address;

  factory TripEndpoint.fromJson(Map<String, dynamic> json) => TripEndpoint(
        point: GeoPoint(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
        address: json['address'] as String?,
      );

  @override
  List<Object?> get props => [point, address];
}

/// A trip as returned by the backend.
class Trip extends Equatable {
  const Trip({
    required this.id,
    required this.status,
    required this.tier,
    required this.pickup,
    required this.dropoff,
    this.routePolyline,
    this.stops = const [],
    this.distanceM,
    this.durationS,
    this.fareEstimate,
    this.fareFinal,
    this.currency = 'USD',
    this.startOtp,
    this.promoCode,
    this.promoDiscount = 0,
    this.paymentMode = 'card',
    this.scheduledAt,
    this.requestedAt,
    this.completedAt,
  });

  final String id;
  final TripStatus status;
  final String tier;
  final TripEndpoint pickup;
  final TripEndpoint dropoff;

  /// Ordered intermediate stops (empty for a direct trip).
  final List<TripStop> stops;
  final String? routePolyline;
  final int? distanceM;
  final int? durationS;
  final double? fareEstimate;
  final double? fareFinal;
  final String currency;
  final String? startOtp;

  /// The promo code applied to this trip, if any.
  final String? promoCode;

  /// Amount discounted by the promo code (0 when none applied).
  final double promoDiscount;

  /// How the rider pays: `card` or `cash`.
  final String paymentMode;

  /// When a scheduled ride is set to begin (null for on-demand rides).
  final DateTime? scheduledAt;

  /// When the trip was requested (present on history responses).
  final DateTime? requestedAt;

  /// When the trip reached a terminal completed state, if it did.
  final DateTime? completedAt;

  /// The fare to display: final if settled, else the estimate.
  double? get fareDisplay => fareFinal ?? fareEstimate;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String,
        status: TripStatus.fromString(json['status'] as String?),
        tier: json['tier'] as String? ?? 'economy',
        pickup: TripEndpoint.fromJson(json['pickup'] as Map<String, dynamic>),
        dropoff: TripEndpoint.fromJson(json['dropoff'] as Map<String, dynamic>),
        stops: (json['stops'] as List<dynamic>? ?? const [])
            .map((s) => TripStop.fromJson(s as Map<String, dynamic>))
            .toList(),
        routePolyline: json['routePolyline'] as String?,
        distanceM: (json['distanceM'] as num?)?.toInt(),
        durationS: (json['durationS'] as num?)?.toInt(),
        fareEstimate: (json['fareEstimate'] as num?)?.toDouble(),
        fareFinal: (json['fareFinal'] as num?)?.toDouble(),
        currency: json['currency'] as String? ?? 'USD',
        startOtp: json['startOtp'] as String?,
        promoCode: json['promoCode'] as String?,
        promoDiscount: (json['promoDiscount'] as num?)?.toDouble() ?? 0,
        paymentMode: json['paymentMode'] as String? ?? 'card',
        scheduledAt: _parseDate(json['scheduledAt']),
        requestedAt: _parseDate(json['requestedAt']),
        completedAt: _parseDate(json['completedAt']),
      );

  static DateTime? _parseDate(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  @override
  List<Object?> get props => [
        id,
        status,
        tier,
        pickup,
        dropoff,
        stops,
        routePolyline,
        distanceM,
        durationS,
        fareEstimate,
        fareFinal,
        currency,
        startOtp,
        promoCode,
        promoDiscount,
        paymentMode,
        scheduledAt,
        requestedAt,
        completedAt,
      ];
}
