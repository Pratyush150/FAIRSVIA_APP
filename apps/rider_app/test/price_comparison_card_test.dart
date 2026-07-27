import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/price_comparison_card.dart';
import 'package:shared_models/shared_models.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

PriceComparison _comparison({required bool oursCheapest}) {
  final quotes = <ProviderQuote>[
    ProviderQuote(
      provider: 'ubernav',
      displayName: 'UberNav',
      productName: 'Economy',
      price: oursCheapest ? 9.00 : 16.67,
      currency: 'USD',
      isOurs: true,
      estimated: false,
    ),
    const ProviderQuote(
      provider: 'empower',
      displayName: 'Empower',
      productName: 'Standard',
      price: 10.85,
      currency: 'USD',
      isOurs: false,
      estimated: true,
    ),
    const ProviderQuote(
      provider: 'uber',
      displayName: 'Uber',
      productName: 'UberX',
      price: 17.12,
      currency: 'USD',
      isOurs: false,
      estimated: true,
    ),
  ]..sort((a, b) => a.price.compareTo(b.price));

  return PriceComparison(
    quotes: quotes,
    cheapestProvider: quotes.first.provider,
    cheapestPrice: quotes.first.price,
    ourPrice: oursCheapest ? 9.00 : 16.67,
    ourRank: quotes.indexWhere((q) => q.isOurs) + 1,
    ourIsCheapest: oursCheapest,
    maxSavings: oursCheapest ? 8.12 : 0.0,
    currency: 'USD',
    disclaimer:
        'Competitor prices are estimates modeled from published fare rates.',
  );
}

void main() {
  group('PriceComparisonCard', () {
    testWidgets('lists every provider with its price', (tester) async {
      await tester
          .pumpWidget(_wrap(PriceComparisonCard(comparison: _comparison(oursCheapest: false))));

      expect(find.text('UberNav'), findsOneWidget);
      expect(find.text('Uber'), findsOneWidget);
      expect(find.text('Empower'), findsOneWidget);
      expect(find.text('\$16.67'), findsOneWidget);
      expect(find.text('\$10.85'), findsOneWidget);
    });

    testWidgets('marks competitor prices as estimates (honesty)',
        (tester) async {
      await tester
          .pumpWidget(_wrap(PriceComparisonCard(comparison: _comparison(oursCheapest: false))));

      // Two competitors → two "est." tags, and the disclaimer line.
      expect(find.text('est.'), findsNWidgets(2));
      expect(
        find.textContaining('estimates from published rates'),
        findsOneWidget,
      );
    });

    testWidgets('celebrates when UberNav is the cheapest', (tester) async {
      await tester
          .pumpWidget(_wrap(PriceComparisonCard(comparison: _comparison(oursCheapest: true))));

      expect(find.textContaining('Cheapest option'), findsOneWidget);
    });

    testWidgets('names the lower option honestly when we are not cheapest',
        (tester) async {
      await tester
          .pumpWidget(_wrap(PriceComparisonCard(comparison: _comparison(oursCheapest: false))));

      // Empower ($10.85) is the min here.
      expect(find.textContaining('Lowest right now: Empower'), findsOneWidget);
    });
  });
}
