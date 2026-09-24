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

// Resolved at runtime so the suite runs on any machine (Linux CI box, Mac,
// GitHub runner): `flutter test` exports FLUTTER_ROOT; otherwise walk up from
// the Dart VM binary ($FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart).
final String _flutterRoot =
    Platform.environment['FLUTTER_ROOT'] ??
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
// `flutter test` runs with cwd = apps/rider_app.
final String _dsFonts = Directory(
  '${Directory.current.path}/../../packages/design_system/fonts',
).resolveSymbolicLinksSync();

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(File(p).readAsBytes().then((b) => b.buffer.asByteData()));
  }
  await loader.load();
}

Future<void> _loadAllFonts() async {
  // Material icon glyphs (savings, verified, local_taxi, help_outline, …).
  await _loadFont('MaterialIcons', [
    '$_flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  // Phosphor icon fonts (the apps' icon family), under the package-qualified
  // families the IconData constants name.
  await _loadFont('packages/design_system/PhosphorRegular', ['$_dsFonts/Phosphor-Regular.ttf']);
  await _loadFont('packages/design_system/PhosphorFill', ['$_dsFonts/Phosphor-Fill.ttf']);
  // The app's real UI face, under the exact package-qualified family the theme
  // asks for.
  await _loadFont('packages/design_system/Inter', [
    '$_dsFonts/Inter-Regular.ttf',
    '$_dsFonts/Inter-Medium.ttf',
    '$_dsFonts/Inter-SemiBold.ttf',
    '$_dsFonts/Inter-Bold.ttf',
    '$_dsFonts/Inter-ExtraBold.ttf',
  ]);
}

PriceComparison _comparison({
  required bool oursCheapest,
  bool demandHigh = false,
}) {
  final quotes = <ProviderQuote>[
    ProviderQuote(
      provider: 'ubernav',
      // Must match the brand baked into the committed goldens: the rebrand
      // regenerated the images but left this fixture on the old name, so every
      // golden here has been failing on the brand row ever since.
      displayName: 'RideVela',
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
  await tester.pumpWidget(
    _frame(
      RepaintBoundary(
        key: const Key('shot'),
        child: PriceComparisonCard(comparison: comparison),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await expectLater(
    find.byKey(const Key('shot')),
    matchesGoldenFile('goldens/price_comparison_$name.png'),
  );
}

void main() {
  // The reference PNGs were rendered on Linux (the CI platform). macOS/Windows
  // rasterize text with different antialiasing (~4% pixel diff, layout
  // identical), so the pixel comparison is only meaningful on Linux.
  if (!Platform.isLinux) {
    test(
      'golden suite',
      () {},
      skip:
          'Goldens are Linux-rendered; text antialiasing differs on '
          '${Platform.operatingSystem}. Run on the Linux CI box.',
    );
    return;
  }
  // The references are the shipped palette and type; an option build
  // (--dart-define=THEME=…) changes both by design, so it has no goldens.
  if (AppColors.variant.isNotEmpty) {
    test(
      'golden suite',
      () {},
      skip: 'Goldens are the default build; THEME=${AppColors.variant} '
          'restyles the card by design.',
    );
    return;
  }
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
