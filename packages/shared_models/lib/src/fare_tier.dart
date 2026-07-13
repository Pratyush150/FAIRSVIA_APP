import 'package:equatable/equatable.dart';

/// A ride tier with its estimated fare for a specific trip.
class FareTier extends Equatable {
  const FareTier({
    required this.tier,
    required this.label,
    required this.capacity,
    required this.fare,
    required this.currency,
    required this.etaSeconds,
  });

  final String tier;
  final String label;
  final int capacity;
  final double fare;
  final String currency;
  final int etaSeconds;

  factory FareTier.fromJson(Map<String, dynamic> json) => FareTier(
        tier: json['tier'] as String,
        label: json['label'] as String,
        capacity: (json['capacity'] as num).toInt(),
        fare: (json['fare'] as num).toDouble(),
        currency: json['currency'] as String? ?? 'INR',
        etaSeconds: (json['etaSeconds'] as num).toInt(),
      );

  @override
  List<Object?> get props => [tier, label, capacity, fare, currency, etaSeconds];
}
