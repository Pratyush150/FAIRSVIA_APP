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
  });

  final double baseFare;

  /// Distance and time components are already multiplied by the surge.
  final double distanceFare;
  final double timeFare;
  final double bookingFee;
  final double surgeMultiplier;
  final double promoDiscount;
  final double tip;

  /// Surge worth calling out (a 1.0× line would only add noise).
  bool get hasSurge => surgeMultiplier > 1.0 + 1e-9;
  bool get hasPromo => promoDiscount > 0;
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
  );

  FareBreakdown copyWith({double? tip}) => FareBreakdown(
    baseFare: baseFare,
    distanceFare: distanceFare,
    timeFare: timeFare,
    bookingFee: bookingFee,
    surgeMultiplier: surgeMultiplier,
    promoDiscount: promoDiscount,
    tip: tip ?? this.tip,
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
  ];
}
