import 'package:equatable/equatable.dart';

/// One provider's price for a trip — either ours (a real fare) or a competitor
/// price MODELED from their published rate card (`estimated == true`).
class ProviderQuote extends Equatable {
  const ProviderQuote({
    required this.provider,
    required this.displayName,
    required this.productName,
    required this.price,
    required this.currency,
    required this.isOurs,
    required this.estimated,
  });

  final String provider;
  final String displayName;
  final String productName;
  final double price;
  final String currency;

  /// True for UberNav's own quote.
  final bool isOurs;

  /// True when the price is a modeled estimate (all competitors), not a live
  /// quote — surfaced in the UI so riders are never misled.
  final bool estimated;

  factory ProviderQuote.fromJson(Map<String, dynamic> json) => ProviderQuote(
        provider: json['provider'] as String,
        displayName: json['displayName'] as String,
        productName: json['productName'] as String? ?? '',
        price: (json['price'] as num).toDouble(),
        currency: json['currency'] as String? ?? 'USD',
        isOurs: json['isOurs'] as bool? ?? false,
        estimated: json['estimated'] as bool? ?? false,
      );

  @override
  List<Object?> get props =>
      [provider, displayName, productName, price, currency, isOurs, estimated];
}

/// The response to POST /comparison/estimate (also embedded in TripEstimate):
/// our fare vs modeled Uber/Lyft/Empower fares for the same trip, with the
/// minimum-price provider flagged.
class PriceComparison extends Equatable {
  const PriceComparison({
    required this.quotes,
    required this.cheapestProvider,
    required this.cheapestPrice,
    required this.ourPrice,
    required this.ourRank,
    required this.ourIsCheapest,
    required this.maxSavings,
    required this.currency,
    required this.disclaimer,
  });

  /// All quotes, cheapest first.
  final List<ProviderQuote> quotes;

  /// Machine id + price of the minimum-price provider.
  final String cheapestProvider;
  final double cheapestPrice;

  final double ourPrice;

  /// 1-based rank of our price among all quotes (1 = cheapest).
  final int ourRank;
  final bool ourIsCheapest;

  /// Largest saving a rider gets by choosing us over a pricier option (>= 0).
  final double maxSavings;

  final String currency;

  /// Honesty note ("competitor prices are estimates …").
  final String disclaimer;

  factory PriceComparison.fromJson(Map<String, dynamic> json) {
    final ours = json['ours'] as Map<String, dynamic>? ?? const {};
    final cheapest = json['cheapest'] as Map<String, dynamic>? ?? const {};
    return PriceComparison(
      quotes: (json['quotes'] as List<dynamic>? ?? const [])
          .map((q) => ProviderQuote.fromJson(q as Map<String, dynamic>))
          .toList(),
      cheapestProvider: cheapest['provider'] as String? ?? '',
      cheapestPrice: (cheapest['price'] as num?)?.toDouble() ?? 0,
      ourPrice: (ours['price'] as num?)?.toDouble() ?? 0,
      ourRank: (ours['rank'] as num?)?.toInt() ?? 0,
      ourIsCheapest: ours['isCheapest'] as bool? ?? false,
      maxSavings: (ours['maxSavings'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'USD',
      disclaimer: json['disclaimer'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [
        quotes,
        cheapestProvider,
        cheapestPrice,
        ourPrice,
        ourRank,
        ourIsCheapest,
        maxSavings,
        currency,
        disclaimer,
      ];
}
