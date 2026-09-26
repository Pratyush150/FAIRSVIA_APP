import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

import 'support/fake_map.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// Owner (2026-09-25): "similar upward pulling screens should not be looking
/// too empty — it should look fully complete". Choosing a ride, dragged
/// all the way up, carries more than its rest content: the ride-type
/// comparison, fare notes, safety features and posters. Nothing overflows on a
/// small phone or at 1.5x text.
///
/// Screenshots: set SHEET_SHOTS to a directory (only then are PNGs written).
void main() {
  final shots = Platform.environment['SHEET_SHOTS'];

  const driver = AssignedDriver(
    id: 'd1',
    name: 'Priya Sharma',
    rating: 4.9,
    vehicleMake: 'Maruti',
    vehicleModel: 'Dzire',
    vehicleColor: 'White',
    plate: 'MH12AB3456',
    phone: '+919876543210',
    etaSec: 240,
  );
  final estimate = TripEstimate(
    distanceM: 4200,
    durationS: 840,
    polyline: '',
    surge: 1,
    currency: 'INR',
    pickup: const GeoPoint(18.52, 73.85),
    dropoff: const GeoPoint(18.53, 73.87),
    tiers: const [
      FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 102,
        currency: 'INR',
        etaSeconds: 180,
      ),
      FareTier(
        tier: 'comfort',
        label: 'Comfort',
        capacity: 4,
        fare: 140,
        currency: 'INR',
        etaSeconds: 240,
      ),
    ],
  );
  final base = TripState(
    trip: Trip(
      id: 't1',
      status: TripStatus.completed,
      tier: 'economy',
      pickup: const TripEndpoint(point: GeoPoint(18.52, 73.85)),
      dropoff: const TripEndpoint(point: GeoPoint(18.53, 73.87)),
      distanceM: 4200,
    ),
    driver: driver,
    estimate: estimate,
    selectedTier: 'economy',
    pickupAddr: 'Central Station, Main Road',
    dropoffAddr: 'City Mall, Ring Road',
  );

  setUpAll(() async {
    if (shots != null) await loadTestFonts();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  final boundary = GlobalKey();

  Future<void> pump(
    WidgetTester tester,
    TripState state, {
    Size size = const Size(411, 914),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            textScaler: TextScaler.linear(textScale),
          ),
          child: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              backgroundColor: const Color(0xFFDDE3E8),
              body: BlocProvider<TripCubit>.value(
                value: cubit,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: RideSheetForPhase(
                    state: state,
                    onSearch: () {},
                    onPickSaved: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Expand'));
    await settle(tester);
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

  /// Scrolls the sheet's content to its end, a page at a time, shooting each.
  Future<void> shootScrolled(WidgetTester tester, String name) async {
    await shoot(tester, name);
    final scroll = find.byType(Scrollable).first;
    for (var i = 1; i <= 3; i++) {
      await tester.drag(scroll, const Offset(0, -500));
      await settle(tester);
      await shoot(tester, '${name}_$i');
    }
  }

  final choose = base.copyWith(phase: TripPhase.choosingRide);

  group('choose ride, expanded', () {
    testWidgets('carries the comparison, fare notes, safety and posters', (
      tester,
    ) async {
      await pump(tester, choose);
      await expand(tester);
      expect(tester.takeException(), isNull);
      await shootScrolled(tester, 'sheet_choose_ride_expanded');
      // Everything in the extras is real: seats from the tiers, the route's
      // own distance, the product's own safety tools.
      // "Compare rides" was removed (owner, 2026-09-26): the Price check
      // card already compares, and the tier list shows seats and pickup.
      expect(find.text('Compare rides', skipOffstage: false), findsNothing);
      expect(find.text('About this fare', skipOffstage: false), findsOneWidget);
      expect(
        find.text('Safety on every ride', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byType(PromoCarousel, skipOffstage: false), findsOneWidget);
    });

    testWidgets('rest view is unchanged: the extras sit below the fold', (
      tester,
    ) async {
      await pump(tester, choose);
      // The Confirm footer still pinned, the first tier still visible.
      expect(find.textContaining('Confirm'), findsWidgets);
      expect(find.text('Economy'), findsWidgets);
    });
  });

  for (final (name, state) in [('choose ride', choose)]) {
    for (final size in const [Size(360, 640), Size(411, 914)]) {
      for (final scale in const [1.0, 1.5, 2.0]) {
        testWidgets(
          '$name: no overflow expanded at ${size.width.toInt()} ×$scale',
          (tester) async {
            await pump(tester, state, size: size, textScale: scale);
            expect(tester.takeException(), isNull);
            await expand(tester);
            expect(tester.takeException(), isNull);
            // Scroll through all of it: every section lays out.
            final scroll = find.byType(Scrollable).first;
            for (var i = 0; i < 6; i++) {
              await tester.drag(scroll, const Offset(0, -400));
              await settle(tester);
              expect(tester.takeException(), isNull);
            }
            if (size.width == 360 && scale == 1.5) {
              await shoot(
                tester,
                'sheet_${name.replaceAll(' ', '_')}_360_x15_end',
              );
            }
          },
        );
      }
    }
  }
}
