import 'package:equatable/equatable.dart';

import 'fare_breakdown.dart';
import 'market.dart';

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

  /// A car of this type is close enough to come: the server only sends an
  /// ETA when one is. Unavailable types are shown dimmed and can't be picked.
  bool get available => etaSeconds != null;

  /// The ride to pre-select: the first one a car can actually do (the list is
  /// cheapest-first), or null when no car of any type is nearby.
  ///
  /// A one-seat ride (a bike taxi) is skipped when anything roomier is
  /// available: it heads the cheapest-first list, but pre-picking it would
  /// book a pillion seat for a rider with a companion or luggage who didn't
  /// look. It is still one tap away, and chosen when it is all there is.
  static String? defaultTier(List<FareTier> tiers) {
    String? single;
    for (final t in tiers) {
      if (!t.available) continue;
      if (t.capacity > 1) return t.tier;
      single ??= t.tier;
    }
    return single;
  }

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
        currency: json['currency'] as String? ?? Market.current.currency,
        etaSeconds: (json['etaSeconds'] as num?)?.toInt(),
        breakdown: FareBreakdown.fromJsonOrNull(json['breakdown']),
      );

  @override
  List<Object?> get props =>
      [tier, label, capacity, fare, currency, etaSeconds, breakdown];
}
