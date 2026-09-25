import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/home/home_cards.dart';
import 'package:rider_app/features/home/home_data.dart';
import 'package:rider_app/features/home/idle_home.dart';
import 'package:rider_app/features/layout/rider_sheet_heights.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

import 'support/fake_map.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// The proportion study (docs/plans/proportion-study-2026-09-25.md): every
/// main rider screen rendered at each candidate map/sheet split, over the
/// painted stand-in map, with the route framed into whatever map is left
/// (as the real camera fit does).
///
/// Always: each candidate lays out without an exception on a 411×914 and a
/// 360×640 phone. Screenshots only when PROPORTION_SHOTS is a directory:
///
///   PROPORTION_SHOTS=../../docs/brand/research/proportions \
///     flutter test test/proportion_study_test.dart
void main() {
  final shots = Platform.environment['PROPORTION_SHOTS'];
  tearDown(() => RiderSheetHeights.debugOverride = null);

  const driver = AssignedDriver(
    name: 'Priya Sharma',
    rating: 4.9,
    vehicleMake: 'Maruti',
    vehicleModel: 'Dzire',
    vehicleColor: 'White',
    plate: 'MH 12 AB 1234',
    phone: '+919876543210',
    etaSec: 240,
  );
  final base = TripState(
    trip: Trip(
      id: 't1',
      status: TripStatus.accepted,
      tier: 'economy',
      startOtp: '4827',
      pickup: const TripEndpoint(point: GeoPoint(18.52, 73.85)),
      dropoff: const TripEndpoint(point: GeoPoint(18.53, 73.87)),
    ),
    driver: driver,
    pickupAddr: 'Shivajinagar, Pune',
    dropoffAddr: 'Pune Railway Station, Agarkar Nagar, Pune',
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
      FareTier(
        tier: 'xl',
        label: 'XL',
        capacity: 6,
        fare: 190,
        currency: 'INR',
        etaSeconds: 300,
      ),
    ],
  );

  ui.Image? car;
  ui.Image? plate;
  setUpAll(() async {
    await loadTestFonts();
    car = await decodeTestImage(
      File(
        '${Directory.current.path}/../../packages/design_system/assets/vehicles/top/economy.png',
      ).readAsBytesSync(),
    );
    final tag = await AppMap.renderPlateTag(
      Market.current.formatPlate(driver.plate!),
    );
    plate = await decodeTestImage(tag.png);
  });

  Widget idleHome() => IdleHome(
    onMenu: () {},
    onRecenter: () {},
    addressLabel: 'Mote Mangal Karyalay Rd, Dattwadi, Pune',
    isSaved: false,
    onToggleSaved: () {},
    searchBar: HomeSearchBar(onTap: () {}, onSchedule: () {}),
    sections: [
      HomeSection(
        child: RecentDestinationsCard(
          items: const [
            RecentDestination(
              address: 'Phoenix Marketcity, Viman Nagar, Pune',
              point: GeoPoint(18.56, 73.91),
            ),
            RecentDestination(
              address: 'Pune Airport, Lohegaon',
              point: GeoPoint(18.58, 73.92),
            ),
          ],
          onPick: (_) {},
        ),
      ),
      ServicesRow(
        items: [
          ServiceItem('Ride', HomeArt.ride, () {}),
          ServiceItem('Pre-book', HomeArt.prebook, () {}),
          ServiceItem('For others', HomeArt.someoneElse, () {}),
          ServiceItem('Saved places', HomeArt.saved, () {}),
        ],
      ),
      const PromoBannerList(kMockPromos),
    ],
  );

  /// One screen: the fake map (route framed between the top chrome and
  /// [routeBottom]) under either the idle Home or the phase sheet.
  Widget screen(
    Size size,
    TripState state, {
    required bool showCar,
    required double routeBottom,
    required GlobalKey boundary,
    required TripCubit cubit,
  }) {
    final idle = state.phase == TripPhase.idle;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          padding: const EdgeInsets.only(top: 24, bottom: 24),
        ),
        child: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            body: BlocProvider<TripCubit>.value(
              value: cubit,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: FakeMapPainter(
                        dark: false,
                        route: !idle,
                        car: showCar ? car : null,
                        plate: showCar ? plate : null,
                        routeTop: 0.13,
                        routeBottom: routeBottom,
                      ),
                    ),
                  ),
                  if (idle)
                    Positioned.fill(child: idleHome())
                  else ...[
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: AppCircleButton(
                            icon: PhosphorIconsRegular.list,
                            tooltip: 'Account menu',
                            onPressed: () {},
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: RideSheetForPhase(
                        state: state,
                        onSearch: () {},
                        savedPlaces: const [],
                        onPickSaved: (_) {},
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> render(
    WidgetTester tester,
    Size size,
    TripState state,
    bool showCar,
    String? name,
  ) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    final key = GlobalKey();
    Widget build(double routeBottom) => screen(
      size,
      state,
      showCar: showCar,
      routeBottom: routeBottom,
      boundary: key,
      cubit: cubit,
    );
    await tester.pumpWidget(build(0.6));
    await settle(tester);
    // Frame the route above the sheet as it actually laid out.
    final sheets = find.byType(AppSheet);
    final top = sheets.evaluate().isEmpty
        ? size.height * 0.6
        : tester.getRect(sheets).top;
    await tester.pumpWidget(build((top - 40) / size.height));
    await settle(tester);
    expect(tester.takeException(), isNull);
    if (shots == null || name == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(shots).createSync(recursive: true);
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  final h = RiderSheetHeights.standard;
  // page → (state, car, candidates as label → proportions)
  final pages = <String, (TripState, bool, Map<String, RiderSheetHeights>)>{
    'home': (
      const TripState(),
      false,
      {
        for (final f in [0.30, 0.35, 0.42])
          '${(f * 100).round()}': h.copyWith(homeMap: f),
      },
    ),
    'choose-ride': (
      base.copyWith(
        phase: TripPhase.choosingRide,
        estimate: estimate,
        selectedTier: 'economy',
      ),
      false,
      {
        for (final f in [0.50, 0.58, 0.62])
          '${(f * 100).round()}': h.copyWith(chooseRide: f),
      },
    ),
    'finding-driver': (
      base.copyWith(phase: TripPhase.searching, estimate: estimate),
      false,
      {
        'fit': h,
        for (final f in [0.28, 0.35, 0.42])
          '${(f * 100).round()}': h.copyWith(searching: f),
      },
    ),
    'driver-en-route': (
      base.copyWith(phase: TripPhase.driverEnRoute),
      true,
      {
        for (final f in [0.36, 0.40, 0.42, 0.50])
          '${(f * 100).round()}': h.copyWith(
            pickupCompact: f,
            onTripCompact: f,
          ),
      },
    ),
    'driver-arrived': (
      base.copyWith(phase: TripPhase.driverArrived),
      true,
      {
        for (final f in [0.36, 0.40, 0.42, 0.50])
          '${(f * 100).round()}': h.copyWith(
            pickupCompact: f,
            onTripCompact: f,
          ),
      },
    ),
    'on-trip': (
      base.copyWith(phase: TripPhase.onTrip, estimate: estimate),
      true,
      {
        for (final f in [0.36, 0.40, 0.42, 0.50])
          '${(f * 100).round()}': h.copyWith(
            pickupCompact: f,
            onTripCompact: f,
          ),
      },
    ),
    'completed': (
      base.copyWith(phase: TripPhase.completed, fareFinal: 102.0),
      false,
      {
        for (final f in [0.85, 1.0])
          '${(f * 100).round()}': h.copyWith(completed: f),
      },
    ),
  };

  for (final MapEntry(key: page, value: (state, showCar, candidates))
      in pages.entries) {
    for (final MapEntry(key: label, value: heights) in candidates.entries) {
      for (final size in const [Size(411, 914), Size(360, 640)]) {
        final small = size.width < 400;
        testWidgets('$page at $label — ${size.width.toInt()}×'
            '${size.height.toInt()}', (tester) async {
          RiderSheetHeights.debugOverride = heights;
          await render(
            tester,
            size,
            state,
            showCar,
            small ? '$page-$label-small' : '$page-$label',
          );
        });
      }
    }
  }
}
