@Tags(['golden'])
library;

import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/price_comparison_card.dart';
import 'package:shared_models/shared_models.dart';

/// Renders [PriceComparisonCard] to PNG files with real app fonts loaded, so the
/// screenshots read exactly like the app — no device or emulator required.
///
///   flutter test test/price_comparison_golden_test.dart --update-goldens
///
/// Output PNGs land in test/goldens/ .

const _flutterRoot = '/home/nova-robotics/flutter';
const _dsFonts =
    '/home/nova-robotics/ubernav/packages/design_system/fonts';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(
      File(p).readAsBytes().then((b) => b.buffer.asByteData()),
    );
  }
  await loader.load();
}

Future<void> _loadAllFonts() async {
  // Material icon glyphs (savings, verified, local_taxi, help_outline, …).
  await _loadFont('MaterialIcons', [
    '$_flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  // The app's real UI face, under the exact package-qualified family the theme
  // asks for.
  await _loadFont('packages/design_system/PlusJakartaSans', [
    '$_dsFonts/PlusJakartaSans-Regular.ttf',
    '$_dsFonts/PlusJakartaSans-Medium.ttf',
    '$_dsFonts/PlusJakartaSans-SemiBold.ttf',
    '$_dsFonts/PlusJakartaSans-Bold.ttf',
    '$_dsFonts/PlusJakartaSans-ExtraBold.ttf',
  ]);
}

PriceComparison _comparison({
  required bool oursCheapest,
  bool demandHigh = false,
}) {
  final quotes = <ProviderQuote>[
    ProviderQuote(
      provider: 'ubernav',
      displayName: 'FairsVia',
      productName: 'Economy',
      price: oursCheapest ? 9.00 : 16.67,
      priceLow: oursCheapest ? 9.00 : 16.67,
      priceHigh: oursCheapest ? 9.00 : 16.67,
      confidence: 'exact',
      currency: 'USD',
      isOurs: true,
      estimated: false,
    ),
    const ProviderQuote(
      provider: 'other1',
      displayName: 'Other app',
      productName: 'Standard',
      price: 12.85,
      priceLow: 12.20,
      priceHigh: 13.50,
      confidence: 'medium',
      currency: 'USD',
      isOurs: false,
      estimated: true,
    ),
    const ProviderQuote(
      provider: 'other2',
      displayName: 'Other app',
      productName: 'Standard',
      price: 17.12,
      priceLow: 16.09,
      priceHigh: 18.15,
      confidence: 'medium',
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
    demandHigh: demandHigh,
    disclaimer:
        'Competitor prices are estimates modeled from published fare rates.',
  );
}

Widget _frame(Widget card) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        backgroundColor: AppColors.surfaceMutedLight,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(width: 360, child: card),
          ),
        ),
      ),
    );

Future<void> _shoot(
  WidgetTester tester,
  String name,
  PriceComparison comparison,
) async {
  await tester.pumpWidget(_frame(
    RepaintBoundary(
      key: const Key('shot'),
      child: PriceComparisonCard(comparison: comparison),
    ),
  ));
  await tester.pumpAndSettle();
  await expectLater(
    find.byKey(const Key('shot')),
    matchesGoldenFile('goldens/price_comparison_$name.png'),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadAllFonts();
  });

  testWidgets('golden: not cheapest (full comparison)', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(400 * 3, 520 * 3);
    addTearDown(tester.view.reset);
    await _shoot(tester, 'not_cheapest', _comparison(oursCheapest: false));
  });

  testWidgets('golden: cheapest with savings', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(400 * 3, 520 * 3);
    addTearDown(tester.view.reset);
    await _shoot(tester, 'cheapest', _comparison(oursCheapest: true));
  });

  testWidgets('golden: high demand flag', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(400 * 3, 560 * 3);
    addTearDown(tester.view.reset);
    await _shoot(
      tester,
      'high_demand',
      _comparison(oursCheapest: false, demandHigh: true),
    );
  });
}
