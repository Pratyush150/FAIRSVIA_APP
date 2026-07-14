import 'package:equatable/equatable.dart';

import 'fare_tier.dart';
import 'geo_point.dart';
import 'trip_stop.dart';

/// The response to POST /trips/estimate: route + a fare option per tier.
class TripEstimate extends Equatable {
  const TripEstimate({
    required this.distanceM,
    required this.durationS,
    required this.polyline,
    required this.surge,
    required this.currency,
    required this.pickup,
    required this.dropoff,
    required this.tiers,
    this.stops = const [],
  });

  final int distanceM;
  final int durationS;
  final String polyline;
  final double surge;
  final String currency;
  final GeoPoint pickup;
  final GeoPoint dropoff;
  final List<FareTier> tiers;
  final List<TripStop> stops;

  /// Distance in statute miles (US market). The backend reports meters.
  double get distanceMi => distanceM / 1609.34;

  factory TripEstimate.fromJson(Map<String, dynamic> json) => TripEstimate(
        distanceM: (json['distanceM'] as num).toInt(),
        durationS: (json['durationS'] as num).toInt(),
        polyline: json['polyline'] as String? ?? '',
        surge: (json['surge'] as num?)?.toDouble() ?? 1.0,
        currency: json['currency'] as String? ?? 'USD',
        pickup: GeoPoint.fromJson(json['pickup'] as Map<String, dynamic>),
        dropoff: GeoPoint.fromJson(json['dropoff'] as Map<String, dynamic>),
        tiers: (json['tiers'] as List<dynamic>)
            .map((t) => FareTier.fromJson(t as Map<String, dynamic>))
            .toList(),
        stops: (json['stops'] as List<dynamic>? ?? const [])
            .map((s) => TripStop.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props => [
        distanceM,
        durationS,
        polyline,
        surge,
        currency,
        pickup,
        dropoff,
        tiers,
        stops,
      ];
}
