import 'package:equatable/equatable.dart';

import 'geo_point.dart';
import 'trip_passenger.dart';
import 'trip_stop.dart';
import 'market.dart';

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
    this.pickupNote,
    this.passenger,
    this.riderName,
    this.riderPhone,
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
    this.cancellationFee,
  });

  final String id;
  final TripStatus status;
  final String tier;
  final TripEndpoint pickup;
  final TripEndpoint dropoff;

  /// A short pickup note from the rider to the driver, if any.
  final String? pickupNote;

  /// Set when this ride was booked for somebody else — see [TripPassenger].
  /// Null on an ordinary ride, where the booker is the passenger.
  final TripPassenger? passenger;

  /// The rider (the booker), as the assigned driver sees them — only on the
  /// driver's view of a live trip (`GET /trips/:id`, `/trips/active`). Null for
  /// the rider's own view, on finished trips and on older backends.
  /// [riderPhone] drives the driver's "Call rider" button; in the pilot it is
  /// the rider's real number (production should hand out a masked one).
  final String? riderName;
  final String? riderPhone;

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

  /// What a late cancel (after the free window) costs. Null on older
  /// backends, in which case the UI keeps its generic wording.
  final double? cancellationFee;

  /// The fare to display: final if settled, else the estimate.
  double? get fareDisplay => fareFinal ?? fareEstimate;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String,
        status: TripStatus.fromString(json['status'] as String?),
        tier: json['tier'] as String? ?? 'economy',
        pickup: TripEndpoint.fromJson(json['pickup'] as Map<String, dynamic>),
        dropoff: TripEndpoint.fromJson(json['dropoff'] as Map<String, dynamic>),
        pickupNote: json['pickupNote'] as String?,
        passenger: TripPassenger.fromJson(json['passenger']),
        riderName: _riderField(json, 'name'),
        riderPhone: _riderField(json, 'phone'),
        stops: (json['stops'] as List<dynamic>? ?? const [])
            .map((s) => TripStop.fromJson(s as Map<String, dynamic>))
            .toList(),
        routePolyline: json['routePolyline'] as String?,
        distanceM: (json['distanceM'] as num?)?.toInt(),
        durationS: (json['durationS'] as num?)?.toInt(),
        fareEstimate: (json['fareEstimate'] as num?)?.toDouble(),
        fareFinal: (json['fareFinal'] as num?)?.toDouble(),
        currency: json['currency'] as String? ?? Market.current.currency,
        startOtp: json['startOtp'] as String?,
        promoCode: json['promoCode'] as String?,
        promoDiscount: (json['promoDiscount'] as num?)?.toDouble() ?? 0,
        paymentMode: json['paymentMode'] as String? ?? 'card',
        scheduledAt: _parseDate(json['scheduledAt']),
        requestedAt: _parseDate(json['requestedAt']),
        completedAt: _parseDate(json['completedAt']),
        cancellationFee: (json['cancellationFee'] as num?)?.toDouble(),
      );

  static String? _riderField(Map<String, dynamic> json, String key) {
    final rider = json['rider'];
    if (rider is! Map) return null;
    final v = (rider[key] as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  static DateTime? _parseDate(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  @override
  List<Object?> get props => [
        id,
        status,
        tier,
        pickup,
        dropoff,
        pickupNote,
        passenger,
        riderName,
        riderPhone,
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
        cancellationFee,
      ];
}
