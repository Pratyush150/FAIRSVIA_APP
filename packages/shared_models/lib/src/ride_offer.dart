import 'package:equatable/equatable.dart';

import 'trip.dart';

/// A dispatch offer pushed to a driver over the socket (`trip:offer`).
class RideOffer extends Equatable {
  const RideOffer({
    required this.tripId,
    required this.pickup,
    required this.dropoff,
    required this.fare,
    required this.tier,
    required this.distanceM,
    required this.durationS,
    required this.expiresInSec,
    this.riderName,
    this.riderRating,
    this.approachDistanceM,
  });

  final String tripId;
  final TripEndpoint pickup;
  final TripEndpoint dropoff;
  final double fare;
  final String tier;

  /// The *trip* leg (pickup → dropoff), not the driver's approach.
  final int distanceM;
  final int durationS;
  final int expiresInSec;

  /// Rider shown on the offer card so the driver isn't accepting blind. Null on
  /// older payloads.
  final String? riderName;
  final double? riderRating;

  /// Straight-line distance (metres) from the driver to the pickup — "how far to
  /// collect the rider". Null when the driver's position was unknown.
  final int? approachDistanceM;

  /// "~X.X mi to pickup" (or "< 500 ft to pickup" when practically there) when
  /// known, else null. Imperial to match the trip-distance line on the same
  /// offer card (US market) — a km figure next to a miles figure read wrong.
  String? get approachLabel {
    final m = approachDistanceM;
    if (m == null || m < 0) return null;
    const metresPerMile = 1609.344;
    const metresPerFoot = 0.3048;
    if (m < 500 * metresPerFoot) return '< 500 ft to pickup';
    return '~${(m / metresPerMile).toStringAsFixed(1)} mi to pickup';
  }

  factory RideOffer.fromJson(Map<String, dynamic> json) {
    final rider = (json['rider'] as Map?)?.cast<String, dynamic>();
    return RideOffer(
      tripId: json['tripId'] as String,
      pickup: TripEndpoint.fromJson(json['pickup'] as Map<String, dynamic>),
      dropoff: TripEndpoint.fromJson(json['dropoff'] as Map<String, dynamic>),
      fare: (json['fare'] as num?)?.toDouble() ?? 0,
      tier: json['tier'] as String? ?? 'economy',
      distanceM: (json['distanceM'] as num?)?.toInt() ?? 0,
      durationS: (json['durationS'] as num?)?.toInt() ?? 0,
      expiresInSec: (json['expiresInSec'] as num?)?.toInt() ?? 15,
      riderName: rider?['name'] as String?,
      riderRating: (rider?['rating'] as num?)?.toDouble(),
      approachDistanceM: (json['approachDistanceM'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [
        tripId,
        pickup,
        dropoff,
        fare,
        tier,
        distanceM,
        durationS,
        expiresInSec,
        riderName,
        riderRating,
        approachDistanceM,
      ];
}
