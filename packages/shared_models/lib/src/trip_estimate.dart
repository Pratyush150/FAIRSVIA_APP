import 'package:equatable/equatable.dart';

import 'fare_breakdown.dart';
import 'fare_tier.dart';
import 'geo_point.dart';
import 'price_comparison.dart';
import 'trip_stop.dart';
import 'market.dart';

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
    this.comparison,
    this.comparisonsByTier = const {},
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

  /// RideVela vs modeled Uber/Lyft/Empower prices for this trip (may be null if
  /// the backend omitted it).
  final PriceComparison? comparison;

  /// Per-tier price checks (`comparisonsByTier` on the wire): each tier's own
  /// fare vs the competitors' matching product (economy vs Uber Go, XL vs
  /// Uber XL, ...). Empty when the backend predates it.
  final Map<String, PriceComparison> comparisonsByTier;

  /// The price check for [tier]: its own entry, else — for economy only —
  /// the legacy [comparison]. Null means "no comparison for this tier": the
  /// UI hides it rather than showing another tier's numbers.
  PriceComparison? comparisonFor(String tier) =>
      comparisonsByTier[tier] ?? (tier == 'economy' ? comparison : null);

  /// Distance in statute miles (US market). The backend reports meters.
  double get distanceMi => distanceM / 1609.34;

  /// The estimate with [tier]'s fare replaced by the server's fresh number
  /// (a `409 PRICE_CHANGED` reply to POST /trips) and the surge updated. Other
  /// tiers keep their quoted fares: the rider is re-confirming the tier they
  /// picked, and the server only re-priced that one. Unknown [tier] → the
  /// surge still updates, no fare changes.
  /// [breakdown] is the server's fresh itemisation of the new fare when the
  /// 409 carried one. Passing null drops the tier's old breakdown rather than
  /// keeping lines that no longer add up to the price being confirmed.
  TripEstimate repriced({
    required String tier,
    required double fare,
    double? surge,
    FareBreakdown? breakdown,
  }) =>
      TripEstimate(
        distanceM: distanceM,
        durationS: durationS,
        polyline: polyline,
        surge: surge ?? this.surge,
        currency: currency,
        pickup: pickup,
        dropoff: dropoff,
        tiers: [
          for (final t in tiers)
            t.tier == tier
                ? FareTier(
                    tier: t.tier,
                    label: t.label,
                    capacity: t.capacity,
                    fare: fare,
                    currency: t.currency,
                    etaSeconds: t.etaSeconds,
                    breakdown: breakdown,
                  )
                : t,
        ],
        stops: stops,
        comparison: comparison,
        comparisonsByTier: comparisonsByTier,
      );

  factory TripEstimate.fromJson(Map<String, dynamic> json) => TripEstimate(
        distanceM: (json['distanceM'] as num).toInt(),
        durationS: (json['durationS'] as num).toInt(),
        polyline: json['polyline'] as String? ?? '',
        surge: (json['surge'] as num?)?.toDouble() ?? 1.0,
        currency: json['currency'] as String? ?? Market.current.currency,
        pickup: GeoPoint.fromJson(json['pickup'] as Map<String, dynamic>),
        dropoff: GeoPoint.fromJson(json['dropoff'] as Map<String, dynamic>),
        tiers: (json['tiers'] as List<dynamic>)
            .map((t) => FareTier.fromJson(t as Map<String, dynamic>))
            .toList(),
        stops: (json['stops'] as List<dynamic>? ?? const [])
            .map((s) => TripStop.fromJson(s as Map<String, dynamic>))
            .toList(),
        comparison: json['comparison'] == null
            ? null
            : PriceComparison.fromJson(
                json['comparison'] as Map<String, dynamic>),
        comparisonsByTier: _parseByTier(json['comparisonsByTier']),
      );

  static Map<String, PriceComparison> _parseByTier(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, PriceComparison>{};
    raw.forEach((k, v) {
      if (k is String && v is Map<String, dynamic>) {
        out[k] = PriceComparison.fromJson(v);
      }
    });
    return out;
  }

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
        comparison,
        comparisonsByTier,
      ];
}
