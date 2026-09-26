import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/trip/price_comparison_card.dart';
import 'package:rider_app/features/trip/sheets/ride_sheets.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

import 'support/fake_map.dart';

/// Owner, 2026-09-26: switching the cab segment (Economy → XL → Premium) must
/// switch the price check to that segment's numbers.

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

ProviderQuote _q(String p, String name, String product, double price,
        {bool ours = false}) =>
    ProviderQuote(
      provider: p,
      displayName: name,
      productName: product,
      price: price,
      priceLow: price,
      priceHigh: price,
      confidence: ours ? 'exact' : 'high',
      currency: 'INR',
      isOurs: ours,
      estimated: !ours,
    );

PriceComparison _cmp(String ourProduct, double ours,
    List<(String, String, String, double)> others) {
  final quotes = [
    _q('ridevela', 'RideVela', ourProduct, ours, ours: true),
    for (final (p, n, prod, price) in others) _q(p, n, prod, price),
  ]..sort((a, b) => a.price.compareTo(b.price));
  final max = quotes.map((q) => q.price).reduce((a, b) => a > b ? a : b);
  return PriceComparison(
    quotes: quotes,
    cheapestProvider: quotes.first.provider,
    cheapestPrice: quotes.first.price,
    ourPrice: ours,
    ourRank: quotes.indexWhere((q) => q.isOurs) + 1,
    ourIsCheapest: quotes.first.isOurs,
    maxSavings: max - ours,
    currency: 'INR',
    demandHigh: false,
    disclaimer: '',
  );
}

final economyCmp = _cmp('Economy', 161, [
  ('uber', 'Uber', 'Uber Go', 192),
  ('ola', 'Ola', 'Ola Mini', 188),
  ('rapido', 'Rapido', 'Rapido Cab Economy', 185),
]);
final xlCmp = _cmp('XL', 255, [
  ('uber', 'Uber', 'Uber XL', 310),
  ('ola', 'Ola', 'Ola Prime SUV', 298),
  ('rapido', 'Rapido', 'Rapido Cab XL', 290),
]);
final premiumCmp = _cmp('Premium', 402, [
  ('uber', 'Uber', 'Uber Premier', 468),
  ('ola', 'Ola', 'Ola Prime Sedan', 455),
]);

TripEstimate _estimate(Map<String, PriceComparison> byTier) => TripEstimate(
      distanceM: 4200,
      durationS: 840,
      polyline: '',
      surge: 1,
      currency: 'INR',
      pickup: const GeoPoint(18.52, 73.85),
      dropoff: const GeoPoint(18.53, 73.87),
      comparison: economyCmp,
      comparisonsByTier: byTier,
      tiers: const [
        FareTier(tier: 'economy', label: 'Economy', capacity: 4, fare: 161,
            currency: 'INR', etaSeconds: 180),
        FareTier(tier: 'xl', label: 'XL', capacity: 6, fare: 255,
            currency: 'INR', etaSeconds: 240),
        FareTier(tier: 'premium', label: 'Premium', capacity: 4, fare: 402,
            currency: 'INR', etaSeconds: 300),
      ],
    );

void main() {
  setUpAll(() async {
    registerFallbackValue('economy');
    await loadTestFonts();
  });

  final chip = find.byKey(const Key('price-comparison-chip'));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Pumps the choose-ride sheet driven by a mock cubit whose selectTier
  /// emits the new selection, the way TripCubit.selectTier does.
  Future<void> pumpSheet(WidgetTester tester, TripEstimate e) async {
    tester.view.physicalSize = const Size(411, 914) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final ctrl = StreamController<TripState>();
    addTearDown(ctrl.close);
    final initial = TripState(
      phase: TripPhase.choosingRide,
      estimate: e,
      selectedTier: 'economy',
      pickupAddr: 'Central Station, Main Road',
      dropoffAddr: 'City Mall, Ring Road',
    );
    final cubit = MockTripCubit();
    whenListen(cubit, ctrl.stream, initialState: initial);
    when(() => cubit.selectTier(any())).thenAnswer((inv) async {
      ctrl.add(cubit.state
          .copyWith(selectedTier: inv.positionalArguments.first as String));
    });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: BlocProvider<TripCubit>.value(
          value: cubit,
          child: BlocBuilder<TripCubit, TripState>(
            builder: (_, s) => Align(
              alignment: Alignment.bottomCenter,
              child: RideSheetForPhase(
                  state: s, onSearch: () {}, onPickSaved: (_) {}),
            ),
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
        of: find.byKey(rideTierListKey), matching: find.text(label)));
    await settle(tester);
  }

  /// Opens the chip's bottom sheet, checks it, closes it.
  Future<void> expectSheet(WidgetTester tester, String title, String oursName,
      List<String> prices) async {
    await tester.tap(chip);
    await settle(tester);
    final sheet = find.byType(BottomSheet);
    Finder inSheet(String t) =>
        find.descendant(of: sheet, matching: find.text(t));
    expect(inSheet(title), findsOneWidget);
    expect(inSheet(oursName), findsOneWidget);
    for (final p in prices) {
      expect(inSheet(p), findsOneWidget, reason: p);
    }
    Navigator.of(tester.element(sheet)).pop();
    await settle(tester);
  }

  /// The pulled-up extras' first section follows the selected tier too.
  void expectExtras(String? title) {
    final f = find.byKey(const Key('price-comparison-section'),
        skipOffstage: false);
    if (title == null) {
      expect(f, findsNothing);
    } else {
      expect(
          find.descendant(of: f, matching: find.text(title), skipOffstage: false),
          findsOneWidget);
    }
  }

  testWidgets('economy → XL → premium: chip and card follow the selection',
      (tester) async {
    await pumpSheet(tester, _estimate({
      'economy': economyCmp,
      'xl': xlCmp,
      'premium': premiumCmp,
    }));
    // Economy.
    expect(find.text('Save ₹31 vs Rapido, Ola, Uber'), findsOneWidget);
    expectExtras('Price check · Economy');
    await expectSheet(tester, 'Price check · Economy', 'RideVela · Economy',
        ['₹161', '₹185', '₹188', '₹192']);

    // XL.
    await pick(tester, 'XL');
    expect(find.text('Save ₹55 vs Rapido, Ola, Uber'), findsOneWidget);
    expect(find.text('Save ₹31 vs Rapido, Ola, Uber'), findsNothing);
    expectExtras('Price check · XL');
    await expectSheet(tester, 'Price check · XL', 'RideVela · XL',
        ['₹255', '₹290', '₹298', '₹310']);

    // Premium.
    await pick(tester, 'Premium');
    expect(find.text('Save ₹66 vs Ola, Uber'), findsOneWidget);
    expectExtras('Price check · Premium');
    await expectSheet(tester, 'Price check · Premium', 'RideVela · Premium',
        ['₹402', '₹455', '₹468']);

    // Back to economy.
    await pick(tester, 'Economy');
    expect(find.text('Save ₹31 vs Rapido, Ola, Uber'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tier without a comparison hides the chip and the card',
      (tester) async {
    await pumpSheet(tester, _estimate({'economy': economyCmp, 'xl': xlCmp}));
    expect(chip, findsOneWidget);
    await pick(tester, 'Premium');
    expect(chip, findsNothing);
    expectExtras(null);
    expect(find.textContaining('Save ₹', skipOffstage: false), findsNothing);
    await pick(tester, 'XL');
    expect(chip, findsOneWidget);
    expect(find.text('Save ₹55 vs Rapido, Ola, Uber'), findsOneWidget);
  });

  testWidgets('old backend (no comparisonsByTier): economy only, XL hidden',
      (tester) async {
    await pumpSheet(tester, _estimate(const {}));
    expect(find.text('Save ₹31 vs Rapido, Ola, Uber'), findsOneWidget);
    await pick(tester, 'XL');
    expect(chip, findsNothing);
    expectExtras(null);
  });

  // Real-font renders of the card per tier (CMP_TIER_SHOTS=<dir>).
  final shots = Platform.environment['CMP_TIER_SHOTS'];
  for (final (name, label, c) in [
    ('economy', 'Economy', economyCmp),
    ('xl', 'XL', xlCmp),
    ('premium', 'Premium', premiumCmp),
  ]) {
    testWidgets('card render: $name', (tester) async {
      final boundary = GlobalKey();
      tester.view.physicalSize = const Size(360, 420) * 2.0;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            backgroundColor: AppColors.surfaceLight,
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: PriceComparisonSection(comparison: c, tierLabel: label),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('RideVela · $label'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (shots == null) return;
      await tester.runAsync(() async {
        final b = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await b.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(shots).createSync(recursive: true);
        File('$shots/cmp_tier_$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
