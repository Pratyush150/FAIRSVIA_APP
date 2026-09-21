import 'package:equatable/equatable.dart';

import 'fare_breakdown.dart';

/// A ride tier with its estimated fare for a specific trip.
class FareTier extends Equatable {
  const FareTier({
    required this.tier,
    required this.label,
    required this.capacity,
    required this.fare,
    required this.currency,
    required this.etaSeconds,
    this.breakdown,
  });

  final String tier;
  final String label;
  final int capacity;
  final double fare;
  final String currency;
  /// Seconds until the nearest car of this tier could be at the pickup;
  /// null when no driver is nearby.
  final int? etaSeconds;

  /// What makes up [fare] — base, distance, time, booking fee, plus surge and
  /// any minimum-fare top-up. Shown behind the "Details" control on the ride
  /// sheet so the price isn't a bare number. Null for an older backend that
  /// doesn't itemise the estimate.
  final FareBreakdown? breakdown;

  factory FareTier.fromJson(Map<String, dynamic> json) => FareTier(
        tier: json['tier'] as String,
        label: json['label'] as String,
        capacity: (json['capacity'] as num).toInt(),
        fare: (json['fare'] as num).toDouble(),
        currency: json['currency'] as String? ?? 'USD',
        etaSeconds: (json['etaSeconds'] as num?)?.toInt(),
        breakdown: FareBreakdown.fromJsonOrNull(json['breakdown']),
      );

  @override
  List<Object?> get props =>
      [tier, label, capacity, fare, currency, etaSeconds, breakdown];
}
