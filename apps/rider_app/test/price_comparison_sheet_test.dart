import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/price_comparison_card.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

import 'support/fake_map.dart';

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

/// Live Pune shape: all three app-cabs on the one regulated fare.
PriceComparison puneEqual() {
  final quotes = [
    _q('ridevela', 'RideVela', 'Economy', 161, ours: true),
    _q('uber', 'Uber', 'Uber Go', 192),
    _q('ola', 'Ola', 'Ola Mini', 192),
    _q('rapido', 'Rapido', 'Rapido Cab Economy', 192),
  ];
  return PriceComparison(
    quotes: quotes,
    cheapestProvider: 'ridevela',
    cheapestPrice: 161,
    ourPrice: 161,
    ourRank: 1,
    ourIsCheapest: true,
    maxSavings: 31,
    currency: 'INR',
    demandHigh: false,
    disclaimer: '',
  );
}

PriceComparison differing({bool oursCheapest = true}) {
  final ours = oursCheapest ? 142.0 : 160.0;
  final quotes = [
    _q('ridevela', 'RideVela', 'Economy', ours, ours: true),
    _q('rapido', 'Rapido', 'Rapido Cab', 151),
    _q('uber', 'Uber', 'Uber Go', 168),
    _q('ola', 'Ola', 'Ola Mini', 175),
  ]..sort((a, b) => a.price.compareTo(b.price));
  return PriceComparison(
    quotes: quotes,
    cheapestProvider: quotes.first.provider,
    cheapestPrice: quotes.first.price,
    ourPrice: ours,
    ourRank: quotes.indexWhere((q) => q.isOurs) + 1,
    ourIsCheapest: oursCheapest,
    maxSavings: oursCheapest ? 175 - ours : 0,
    currency: 'INR',
    demandHigh: false,
    disclaimer: '',
  );
}

void main() {
  final shots = Platform.environment['SHEET_SHOTS'];
  setUpAll(() async {
    if (shots != null) await loadTestFonts();
  });

  TripEstimate estimate(PriceComparison? c) => TripEstimate(
        distanceM: 4200,
        durationS: 840,
        polyline: '',
        surge: 1,
        currency: 'INR',
        pickup: const GeoPoint(18.52, 73.85),
        dropoff: const GeoPoint(18.53, 73.87),
        comparison: c,
        tiers: const [
          FareTier(tier: 'economy', label: 'Economy', capacity: 4, fare: 161,
              currency: 'INR', etaSeconds: 180),
          FareTier(tier: 'comfort', label: 'Comfort', capacity: 4, fare: 210,
              currency: 'INR', etaSeconds: 240),
        ],
      );

  TripState state(PriceComparison? c) => TripState(
        phase: TripPhase.choosingRide,
        estimate: estimate(c),
        selectedTier: 'economy',
        pickupAddr: 'Central Station, Main Road',
        dropoffAddr: 'City Mall, Ring Road',
      );

  final boundary = GlobalKey();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final b =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(shots).createSync(recursive: true);
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> pumpSheet(
    WidgetTester tester,
    TripState s, {
    bool dark = false,
    Size size = const Size(360, 800),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    AppColors.syncBrightness(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => AppColors.syncBrightness(Brightness.light));
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: s);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(top: 24, bottom: 24),
          textScaler: TextScaler.linear(textScale),
        ),
        child: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            backgroundColor:
                dark ? const Color(0xFF2A3036) : const Color(0xFFDDE3E8),
            body: BlocProvider<TripCubit>.value(
              value: cubit,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: RideSheetForPhase(
                  state: s, onSearch: () {}, onPickSaved: (_) {}),
              ),
            ),
          ),
        ),
      ),
    ));
    await settle(tester);
  }

  Future<void> pumpCard(WidgetTester tester, PriceComparison c,
      {bool dark = false, double textScale = 1.0}) async {
    tester.view.physicalSize = const Size(360, 620) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    AppColors.syncBrightness(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => AppColors.syncBrightness(Brightness.light));
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 620),
          textScaler: TextScaler.linear(textScale),
        ),
        child: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            backgroundColor:
                dark ? AppColors.surfaceDark : AppColors.surfaceLight,
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: PriceComparisonSection(comparison: c),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  group('resting sheet chip', () {
    testWidgets('absent without a comparison; Confirm + first tier shown',
        (tester) async {
      await pumpSheet(tester, state(null));
      expect(find.byKey(const Key('price-comparison-chip')), findsNothing);
      expect(find.text('Economy'), findsWidgets);
    });

    testWidgets('present with a comparison, honest savings copy',
        (tester) async {
      await pumpSheet(tester, state(puneEqual()));
      expect(find.byKey(const Key('price-comparison-chip')), findsOneWidget);
      expect(
        find.text('Save ₹31 vs Uber, Ola, Rapido'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no savings claim when we are not cheapest', (tester) async {
      await pumpCard(tester, differing(oursCheapest: false));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: PriceComparisonChip(comparison: differing(oursCheapest: false)),
        ),
      ));
      expect(find.textContaining('Compare prices'), findsOneWidget);
      expect(find.textContaining('save'), findsNothing);
    });

    for (final dark in [false, true]) {
      testWidgets('shots: resting sheet (${dark ? 'dark' : 'light'})',
          (tester) async {
        await pumpSheet(tester, state(puneEqual()), dark: dark);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'cmp_card_rest_${dark ? 'dark' : 'light'}');
      });
    }

    testWidgets('no overflow at 360dp and 1.5x text', (tester) async {
      await pumpSheet(tester, state(puneEqual()), textScale: 1.5);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'cmp_card_rest_1_5x');
    });
  });

  group('full card', () {
    testWidgets('groups equal competitor fares into one row', (tester) async {
      await pumpCard(tester, puneEqual());
      expect(find.text('Price check'), findsOneWidget);
      expect(find.text('RideVela'), findsOneWidget);
      expect(find.text('Uber · Ola · Rapido'), findsOneWidget);
      expect(find.textContaining('Uber Go · Ola Mini · Rapido Cab Economy'),
          findsOneWidget);
      expect(find.text('₹192'), findsOneWidget);
      expect(find.text('₹161'), findsOneWidget);
      expect(find.text('Cheapest'), findsOneWidget);
      expect(find.text('Govt-approved app-cab fare · actual prices may vary'),
          findsOneWidget);
      expect(find.textContaining('Estimates from published'), findsNothing);
    });

    testWidgets('one row per provider when fares differ; ours first',
        (tester) async {
      await pumpCard(tester, differing());
      for (final t in ['₹142', '₹151', '₹168', '₹175']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(tester.getTopLeft(find.text('RideVela')).dy,
          lessThan(tester.getTopLeft(find.text('Rapido')).dy));
      expect(find.text('Cheapest'), findsOneWidget);
    });

    testWidgets('names the lower option when we are not cheapest',
        (tester) async {
      await pumpCard(tester, differing(oursCheapest: false));
      expect(find.textContaining('Lowest right now: Rapido'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      for (final (name, c) in [('pune', puneEqual()), ('diff', differing())]) {
        testWidgets('shots: full card $name (${dark ? 'dark' : 'light'})',
            (tester) async {
          await pumpCard(tester, c, dark: dark);
          expect(tester.takeException(), isNull);
          await shoot(tester, 'cmp_card_full_${name}_${dark ? 'dark' : 'light'}');
        });
      }
    }

    testWidgets('no overflow at 360dp and 1.5x text', (tester) async {
      await pumpCard(tester, differing(), textScale: 1.5);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'cmp_card_full_1_5x');
    });
  });
}
