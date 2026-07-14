import 'package:equatable/equatable.dart';

/// The result of pricing a promo code against a fare subtotal (server-computed).
class PromoQuote extends Equatable {
  const PromoQuote({
    required this.code,
    required this.kind,
    required this.discount,
    required this.subtotal,
    required this.net,
  });

  /// The normalized (upper-cased) code the discount applies to.
  final String code;

  /// `flat` or `percent`.
  final String kind;

  /// Amount taken off the subtotal, in the fare currency.
  final double discount;

  /// Fare before the discount.
  final double subtotal;

  /// Fare after the discount (`subtotal - discount`, floored at 0).
  final double net;

  factory PromoQuote.fromJson(Map<String, dynamic> json) => PromoQuote(
        code: json['code'] as String,
        kind: json['kind'] as String? ?? 'flat',
        discount: (json['discount'] as num).toDouble(),
        subtotal: (json['subtotal'] as num).toDouble(),
        net: (json['net'] as num).toDouble(),
      );

  @override
  List<Object?> get props => [code, kind, discount, subtotal, net];
}
