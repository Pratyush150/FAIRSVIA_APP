import 'package:equatable/equatable.dart';

/// Itemised components of a settled fare, as carried on the `trip:completed`
/// socket event and `GET /payments/:tripId/receipt` (`breakdown`). Null on
/// the wire for trips settled before the backend recorded it.
///
/// The headline fare stays authoritative — a clamp or minimum-fare floor can
/// move it off the sum of these parts — so this is presentational only.
class FareBreakdown extends Equatable {
  const FareBreakdown({
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.bookingFee,
    this.surgeMultiplier = 1,
    this.promoDiscount = 0,
    this.tip = 0,
    this.minimumFareAdjustment = 0,
    this.fareAdjustment = 0,
    this.priceMatchDiscount = 0,
    this.fareBasis,
    this.endedEarly = false,
    this.endReason,
  });

  final double baseFare;

  /// Distance and time components are already multiplied by the surge.
  final double distanceFare;
  final double timeFare;
  final double bookingFee;
  final double surgeMultiplier;
  final double promoDiscount;
  final double tip;

  /// Top-up to the tier's minimum fare when the metered parts fell short, so
  /// the lines add up to the headline (0 when the minimum didn't apply).
  final double minimumFareAdjustment;

  /// Signed move from the metered parts to the charged fare when the
  /// up-front quote bounded it (not a minimum-fare top-up).
  final double fareAdjustment;

  /// How much the up-front quote was lowered to undercut the cheapest
  /// competitor estimate (RideVela price match); 0 when it didn't apply.
  final double priceMatchDiscount;

  /// How the headline was reached: `metered` (distance + time driven),
  /// `minimum` (the tier's minimum fare) or `estimate` (bounded by / fell back
  /// to the up-front price). Null for trips settled before it was recorded.
  final String? fareBasis;

  /// The driver ended the trip before the drop-off, and why.
  final bool endedEarly;
  final String? endReason;

  bool get hasMinimumFare => minimumFareAdjustment > 0;
  bool get hasFareAdjustment => fareAdjustment.abs() >= 0.005;

  /// One truthful line on how the fare was worked out; null when unknown.
  String? get basisNote {
    final early = endedEarly
        ? 'Trip ended before the drop-off'
            '${endReason == null || endReason!.isEmpty ? '' : ' ($endReason)'}. '
        : '';
    final how = switch (fareBasis) {
      'metered' => 'Metered on the distance and time driven.',
      'minimum' => 'Minimum fare applied.',
      'estimate' => endedEarly
          ? 'Capped at your up-front price.'
          : 'Based on your up-front price.',
      _ => null,
    };
    if (how == null && early.isEmpty) return null;
    return '$early${how ?? ''}'.trim();
  }

  /// Surge worth calling out (a 1.0× line would only add noise).
  bool get hasSurge => surgeMultiplier > 1.0 + 1e-9;
  bool get hasPromo => promoDiscount > 0;
  bool get hasPriceMatch => priceMatchDiscount >= 0.005;
  bool get hasTip => tip > 0;

  /// Parses the wire shape; returns null when [json] is null (older trips).
  static FareBreakdown? fromJsonOrNull(Object? json) =>
      json is Map<String, dynamic> ? FareBreakdown.fromJson(json) : null;

  factory FareBreakdown.fromJson(Map<String, dynamic> json) => FareBreakdown(
    baseFare: (json['baseFare'] as num?)?.toDouble() ?? 0,
    distanceFare: (json['distanceFare'] as num?)?.toDouble() ?? 0,
    timeFare: (json['timeFare'] as num?)?.toDouble() ?? 0,
    bookingFee: (json['bookingFee'] as num?)?.toDouble() ?? 0,
    surgeMultiplier: (json['surgeMultiplier'] as num?)?.toDouble() ?? 1,
    promoDiscount: (json['promoDiscount'] as num?)?.toDouble() ?? 0,
    tip: (json['tip'] as num?)?.toDouble() ?? 0,
    minimumFareAdjustment:
        (json['minimumFareAdjustment'] as num?)?.toDouble() ?? 0,
    fareAdjustment: (json['fareAdjustment'] as num?)?.toDouble() ?? 0,
    priceMatchDiscount:
        (json['priceMatchDiscount'] as num?)?.toDouble() ?? 0,
    fareBasis: json['fareBasis'] as String?,
    endedEarly: json['endedEarly'] == true,
    endReason: json['endReason'] as String?,
  );

  FareBreakdown copyWith({double? tip}) => FareBreakdown(
    baseFare: baseFare,
    distanceFare: distanceFare,
    timeFare: timeFare,
    bookingFee: bookingFee,
    surgeMultiplier: surgeMultiplier,
    promoDiscount: promoDiscount,
    tip: tip ?? this.tip,
    minimumFareAdjustment: minimumFareAdjustment,
    fareAdjustment: fareAdjustment,
    priceMatchDiscount: priceMatchDiscount,
    fareBasis: fareBasis,
    endedEarly: endedEarly,
    endReason: endReason,
  );

  @override
  List<Object?> get props => [
    baseFare,
    distanceFare,
    timeFare,
    bookingFee,
    surgeMultiplier,
    promoDiscount,
    tip,
    minimumFareAdjustment,
    fareAdjustment,
    priceMatchDiscount,
    fareBasis,
    endedEarly,
    endReason,
  ];
}
