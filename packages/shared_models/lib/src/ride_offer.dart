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
  });

  final String tripId;
  final TripEndpoint pickup;
  final TripEndpoint dropoff;
  final double fare;
  final String tier;
  final int distanceM;
  final int durationS;
  final int expiresInSec;

  factory RideOffer.fromJson(Map<String, dynamic> json) => RideOffer(
        tripId: json['tripId'] as String,
        pickup: TripEndpoint.fromJson(json['pickup'] as Map<String, dynamic>),
        dropoff: TripEndpoint.fromJson(json['dropoff'] as Map<String, dynamic>),
        fare: (json['fare'] as num?)?.toDouble() ?? 0,
        tier: json['tier'] as String? ?? 'economy',
        distanceM: (json['distanceM'] as num?)?.toInt() ?? 0,
        durationS: (json['durationS'] as num?)?.toInt() ?? 0,
        expiresInSec: (json['expiresInSec'] as num?)?.toInt() ?? 15,
      );

  @override
  List<Object?> get props =>
      [tripId, pickup, dropoff, fare, tier, distanceM, durationS, expiresInSec];
}
