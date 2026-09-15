import 'dart:math' as math;

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
    this.pickupNote,
    this.approachDistanceM,
    this.approachEtaS,
    this.approachSource,
    this.surge = 1,
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

  /// A short pickup note from the rider ("meet at the lobby"), shown on the
  /// offer so the driver knows where to collect them. Null when none.
  final String? pickupNote;

  /// Distance (metres) from the driver to the pickup — "how far to collect the
  /// rider". Road distance when [approachSource] is `road`, straight-line when
  /// `straight`; null when the driver's position was unknown.
  final int? approachDistanceM;

  /// Estimated seconds for the driver to reach the pickup (road ETA, or a
  /// nominal-pace guess when [approachSource] is `straight`). Null on older
  /// payloads or when the position was unknown.
  final int? approachEtaS;

  /// How the approach figures were derived: `road`, `straight` or `unknown`.
  final String? approachSource;

  /// Surge multiplier baked into [fare] (1 = no surge).
  final double surge;

  /// True when the fare carries a surge premium worth calling out.
  bool get hasSurge => surge > 1;

  /// "1.3× surge" for the offer-card badge; null when there is no surge.
  String? get surgeLabel =>
      hasSurge ? '${surge.toStringAsFixed(1)}× surge' : null;

  static const _metresPerMile = 1609.344;
  static const _metresPerFoot = 0.3048;

  /// "X.X mi" ("~X.X mi" when [approx]), or "< 500 ft" when practically
  /// there. Imperial to match the trip-distance line on the same offer card
  /// (US market) — a km figure next to a miles figure read wrong.
  static String _milesText(int m, {required bool approx}) {
    if (m < 500 * _metresPerFoot) return '< 500 ft';
    final miles = (m / _metresPerMile).toStringAsFixed(1);
    return approx ? '~$miles mi' : '$miles mi';
  }

  /// Whole minutes for a readout, never "0 min" for a short hop.
  static int _minutes(int seconds) => math.max(1, (seconds / 60).round());

  /// "~X.X mi to pickup" (or "< 500 ft to pickup" when practically there) when
  /// known, else null. Distance only — see [approachEtaLabel] for the
  /// ETA-first form.
  String? get approachLabel {
    final m = approachDistanceM;
    if (m == null || m < 0) return null;
    return '${_milesText(m, approx: true)} to pickup';
  }

  /// Uber-style "N min · X.X mi to pickup" when the server sent an approach
  /// ETA (no "~" when the figures come from a road route); falls back to the
  /// distance-only [approachLabel], and to null when nothing is known.
  String? get approachEtaLabel {
    final m = approachDistanceM;
    final eta = approachEtaS;
    if (m == null || m < 0 || eta == null || eta < 0) return approachLabel;
    final miles = _milesText(m, approx: approachSource != 'road');
    return '${_minutes(eta)} min · $miles to pickup';
  }

  /// The trip leg as "X.X mi · N min" (distance only when the payload carried
  /// no duration).
  String get tripLabel {
    final miles = (distanceM / _metresPerMile).toStringAsFixed(1);
    if (durationS <= 0) return '$miles mi';
    return '$miles mi · ${_minutes(durationS)} min';
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
      pickupNote: json['pickupNote'] as String?,
      approachDistanceM: (json['approachDistanceM'] as num?)?.toInt(),
      approachEtaS: (json['approachEtaS'] as num?)?.toInt(),
      approachSource: json['approachSource'] as String?,
      surge: (json['surge'] as num?)?.toDouble() ?? 1,
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
        pickupNote,
        approachDistanceM,
        approachEtaS,
        approachSource,
        surge,
      ];
}
