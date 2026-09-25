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

/// The completed sheet pulled fully up: the trip card (car, driver, route,
/// real distance/time) sits under the tip section, and nothing overflows on
/// a 360dp phone at 1.5x text. PNGs only when SHEET_SHOTS is set.
void main() {
  final shots = Platform.environment['SHEET_SHOTS'];
  setUpAll(() async {
    if (shots != null) await loadTestFonts();
  });

  const driver = AssignedDriver(
    name: 'Priya Sharma',
    rating: 4.9,
    vehicleMake: 'Maruti',
    vehicleModel: 'Dzire',
    vehicleColor: 'White',
    plate: 'MH12AB3456',
  );
  final state = TripState(
    phase: TripPhase.completed,
    fareFinal: 75,
    driver: driver,
    pickupAddr: 'Central Station, Main Road',
    dropoffAddr: 'City Mall, Ring Road',
    trip: const Trip(
      id: 't1',
      status: TripStatus.completed,
      tier: 'economy',
      pickup: TripEndpoint(point: GeoPoint(18.52, 73.85)),
      dropoff: TripEndpoint(point: GeoPoint(18.53, 73.87)),
      distanceM: 4200,
      durationS: 840,
      fareFinal: 75,
      currency: 'INR',
      paymentMode: 'cash',
    ),
  );

  final boundary = GlobalKey();

  Future<void> pump(WidgetTester tester, Size size, double scale) async {
    tester.view.physicalSize = size * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            body: BlocProvider<TripCubit>.value(
              value: cubit,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                // Unbounded height: the whole sheet, as if pulled fully up.
                child: SingleChildScrollView(
                    child: CompletedSheet(state: state)),
              ),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('fully up it shows the trip with real data', (tester) async {
    await pump(tester, const Size(411, 2200), 1.0);
    expect(tester.takeException(), isNull);
    expect(find.text('Your trip'), findsOneWidget);
    expect(find.byType(VehicleGlyph), findsOneWidget);
    expect(find.byType(RouteTimeline), findsOneWidget);
    expect(find.text('Central Station, Main Road'), findsOneWidget);
    expect(find.text('City Mall, Ring Road'), findsOneWidget);
    expect(find.textContaining('with Priya Sharma'), findsOneWidget);
    // The total is still said once.
    expect(find.textContaining('Total '), findsOneWidget);
    if (shots != null) {
      await tester.runAsync(() async {
        final b = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/sheet_completed.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });

  testWidgets('no overflow at 360dp and 1.5x text', (tester) async {
    await pump(tester, const Size(360, 3000), 1.5);
    expect(tester.takeException(), isNull);
    expect(find.text('Your trip'), findsOneWidget);
  });
}
