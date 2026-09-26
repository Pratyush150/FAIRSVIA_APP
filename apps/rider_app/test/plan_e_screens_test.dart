// Plan E — "Ink & Paper" screenshots: the rider's key sheets rendered with
// the real fonts and art, phone-sized, light and dark.
//
// Renders in every build (so it also checks nothing overflows), but writes
// PNGs only when asked, so CI never touches docs/:
//
//   PLAN_E_OUT=../../docs/brand/research/plan-e \
//     flutter test --dart-define=THEME=ink test/plan_e_screens_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

class MockPayments extends Mock implements PaymentsRemoteDataSource {}

final String _flutterRoot =
    Platform.environment['FLUTTER_ROOT'] ??
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
final String _dsFonts = Directory(
  '${Directory.current.path}/../../packages/design_system/fonts',
).resolveSymbolicLinksSync();
final String? _out = Platform.environment['PLAN_E_OUT'];

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(File(f).readAsBytes().then((b) => b.buffer.asByteData()));
  }
  await loader.load();
}

Future<void> _loadFonts() async {
  await _font('MaterialIcons', [
    '$_flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  const ds = 'packages/design_system';
  await _font('$ds/PhosphorRegular', ['$_dsFonts/Phosphor-Regular.ttf']);
  await _font('$ds/PhosphorFill', ['$_dsFonts/Phosphor-Fill.ttf']);
  await _font('$ds/PhosphorLight', ['$_dsFonts/Phosphor-Light.ttf']);
  await _font('$ds/InstrumentSerif', ['$_dsFonts/InstrumentSerif-Regular.ttf']);
  await _font('$ds/RideVelaCaps', ['$_dsFonts/RideVelaCaps-SemiBold.ttf']);
  await _font('$ds/Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'])
      '$_dsFonts/Inter-$w.ttf',
  ]);
}

const _size = Size(411, 914);

const _breakdown = FareBreakdown(
  baseFare: 40,
  distanceFare: 46.5,
  timeFare: 12,
  bookingFee: 5,
);

const _tiers = [
  FareTier(
    tier: 'economy',
    label: 'Economy',
    capacity: 4,
    fare: 103.5,
    currency: 'INR',
    etaSeconds: 180,
    breakdown: _breakdown,
  ),
  FareTier(
    tier: 'comfort',
    label: 'Comfort',
    capacity: 4,
    fare: 142,
    currency: 'INR',
    etaSeconds: 300,
    breakdown: _breakdown,
  ),
  FareTier(
    tier: 'xl',
    label: 'XL',
    capacity: 6,
    fare: 188,
    currency: 'INR',
    etaSeconds: 420,
    breakdown: _breakdown,
  ),
  FareTier(
    tier: 'premium',
    label: 'Premium',
    capacity: 4,
    fare: 246,
    currency: 'INR',
    etaSeconds: 540,
    breakdown: _breakdown,
  ),
];

const _estimate = TripEstimate(
  distanceM: 6200,
  durationS: 1260,
  polyline: '',
  surge: 1,
  currency: 'INR',
  pickup: GeoPoint(18.52, 73.85),
  dropoff: GeoPoint(18.53, 73.87),
  tiers: _tiers,
);

const _driver = AssignedDriver(
  name: 'Rahul',
  rating: 4.9,
  vehicleMake: 'Maruti',
  vehicleModel: 'Dzire',
  vehicleColor: 'White',
  plate: 'MH 12 AB 1234',
  phone: '+919800000000',
  etaSec: 180,
);

final _trip = Trip(
  id: 't1',
  status: TripStatus.accepted,
  tier: 'economy',
  startOtp: '4827',
  currency: 'INR',
  paymentMode: 'cash',
  pickup: const TripEndpoint(
    point: GeoPoint(18.52, 73.85),
    address: 'FC Road, Shivajinagar, Pune',
  ),
  dropoff: const TripEndpoint(
    point: GeoPoint(18.53, 73.87),
    address: 'Phoenix Marketcity, Viman Nagar, Pune',
  ),
  requestedAt: DateTime(2026, 9, 24, 18, 40),
);

TripState _state(TripPhase phase) => TripState(
  phase: phase,
  trip: _trip,
  estimate: _estimate,
  selectedTier: 'economy',
  driver: _driver,
  pickupAddr: 'FC Road, Shivajinagar, Pune',
  dropoffAddr: 'Phoenix Marketcity, Viman Nagar, Pune',
  fareFinal: 103.5,
  breakdown: _breakdown,
  receipt: const Receipt(
    tripId: 't1',
    fare: 103.5,
    currency: 'INR',
    method: 'cash',
  ),
);

void main() {
  setUpAll(() async {
    Market.current = Market.india;
    await _loadFonts();
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget screen, {
    required bool dark,
    Future<void> Function()? then,
  }) async {
    tester.view.physicalSize = _size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    AppColors.syncBrightness(dark ? Brightness.dark : Brightness.light);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: _size,
              padding: EdgeInsets.only(top: 24, bottom: 16),
              // Not Reduce Motion: under it, opening the completed sheet's
              // breakdown trips a RenderAnimatedSize assertion (zero-duration
              // AnimatedSize in sheet_shell.dart — pre-existing, every build).
              // The frames are stepped through below instead.
            ),
            child: screen,
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (then != null) await then();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Decode the vehicle art for real (images load off the fake clock).
    await tester.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    final out = _out;
    if (out == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$out/${name}_${dark ? 'dark' : 'light'}.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Widget sheet(TripState s) {
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: s);
    return Scaffold(
      body: BlocProvider<TripCubit>.value(
        value: cubit,
        child: Stack(
          children: [
            const Positioned.fill(child: MapPlaceholder(note: '')),
            Align(
              alignment: Alignment.bottomCenter,
              child: RideSheetForPhase(
                state: s,
                onSearch: () {},
                onPickSaved: (_) {},
                savedPlaces: const [
                  SavedPlace(
                    id: 'h',
                    label: 'Home',
                    point: GeoPoint(18.51, 73.84),
                    address: 'Prabhat Road, Erandwane, Pune',
                  ),
                  SavedPlace(
                    id: 'w',
                    label: 'Work',
                    point: GeoPoint(18.55, 73.89),
                    address: 'World Trade Center, Kharadi, Pune',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    group(mode, () {
      testWidgets('where to', (t) async {
        await shoot(
          t,
          '01_where_to',
          sheet(_state(TripPhase.idle)),
          dark: dark,
        );
      });
      testWidgets('choose ride', (t) async {
        await shoot(
          t,
          '02_choose_ride',
          sheet(_state(TripPhase.choosingRide)),
          dark: dark,
        );
      });
      testWidgets('finding driver', (t) async {
        await shoot(
          t,
          '03_finding',
          sheet(_state(TripPhase.searching)),
          dark: dark,
        );
      });
      testWidgets('driver on the way', (t) async {
        await shoot(
          t,
          '04_driver',
          sheet(_state(TripPhase.driverEnRoute)),
          dark: dark,
        );
      });
      testWidgets('on trip', (t) async {
        await shoot(
          t,
          '05_on_trip',
          sheet(_state(TripPhase.onTrip)),
          dark: dark,
        );
      });
      testWidgets('completed, receipt open', (t) async {
        await shoot(
          t,
          '06_completed',
          sheet(_state(TripPhase.completed)),
          dark: dark,
          then: () async {
            await t.tap(find.textContaining('Total'));
            await t.pump(const Duration(milliseconds: 50));
          },
        );
      });
      testWidgets('receipt page', (t) async {
        final payments = MockPayments();
        when(() => payments.receipt('t1')).thenAnswer(
          (_) async => const Receipt(
            tripId: 't1',
            fare: 103.5,
            currency: 'INR',
            tip: 20,
            method: 'cash',
            status: 'succeeded',
            breakdown: _breakdown,
          ),
        );
        await shoot(
          t,
          '07_receipt',
          ReceiptPage(
            payments: payments,
            trip: Trip(
              id: 't1',
              status: TripStatus.completed,
              tier: 'economy',
              currency: 'INR',
              pickup: _trip.pickup,
              dropoff: _trip.dropoff,
              fareFinal: 103.5,
              requestedAt: DateTime(2026, 9, 24, 18, 40),
            ),
          ),
          dark: dark,
        );
      });
      testWidgets('splash', (t) async {
        await shoot(
          t,
          '08_splash',
          BrandSplash(name: 'RideVela', onDone: () {}),
          dark: dark,
          then: () async {
            await t.pump(AppBrand.splashTotal);
          },
        );
      });
    });
  }
}
