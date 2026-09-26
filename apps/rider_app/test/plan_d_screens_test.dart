// Plan D ("Local Colour", THEME=local) sheets, rendered for review.
//
// In every build this is a smoke test: the key sheets pump in light and dark
// without an exception, and — in a Plan D build — carry D's signature pieces
// (skyline, kolam radar, pay strip, rate card). Writing PNGs is opt-in, so CI
// never touches docs/:
//
//   PLAN_D_SHOTS=../../docs/brand/research/plan-d \
//       flutter test test/plan_d_screens_test.dart --dart-define=THEME=local
//
// The map behind the sheet is a drawn stand-in (Google Maps is a platform
// view and does not render in a widget test); on it, the pickup kolam is
// painted with the same geometry AppMap uses, as an approximation.
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
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

const _fonts = '../../packages/design_system/fonts';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        File('$_fonts/$f').readAsBytes().then((b) => b.buffer.asByteData()),
      );
    }
    await loader.load();
  }

  await load('packages/design_system/PhosphorRegular', [
    'Phosphor-Regular.ttf',
  ]);
  await load('packages/design_system/PhosphorFill', ['Phosphor-Fill.ttf']);
  await load('packages/design_system/Inter', [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
  ]);
  await load('packages/design_system/AnekLatin', [
    'AnekLatin-Regular.ttf',
    'AnekLatin-Medium.ttf',
    'AnekLatin-SemiBold.ttf',
    'AnekLatin-Bold.ttf',
  ]);
  // Material's own text (e.g. a bare Text with no theme family) — Roboto is
  // not bundled; Inter stands in so nothing renders as test boxes.
  await load('Roboto', ['Inter-Regular.ttf', 'Inter-Medium.ttf']);
}

/// A quiet stand-in for the map: warm land, a few streets, and (for the
/// finding-driver shot) the pickup kolam.
class _FakeMap extends CustomPainter {
  _FakeMap({required this.dark, this.kolam = false});
  final bool dark;
  final bool kolam;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dark ? const Color(0xFF1A1E21) : const Color(0xFFF1EBE0),
    );
    final road = Paint()
      ..color = dark ? const Color(0xFF3A4147) : const Color(0xFFFFFDF8)
      ..strokeWidth = 10;
    final minor = Paint()
      ..color = dark ? const Color(0xFF343A40) : const Color(0xFFFFFDF8)
      ..strokeWidth = 5;
    for (var y = 60.0; y < size.height; y += 140) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 40), minor);
    }
    for (var x = 40.0; x < size.width; x += 120) {
      canvas.drawLine(Offset(x, 0), Offset(x + 30, size.height), minor);
    }
    canvas.drawLine(
      Offset(0, size.height * 0.2),
      Offset(size.width, size.height * 0.34),
      road,
    );
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.12),
      50,
      Paint()..color = dark ? const Color(0xFF1C2E23) : const Color(0xFFD9E6CF),
    );
    if (kolam) {
      final c = Offset(size.width / 2, size.height * 0.24);
      canvas.save();
      canvas.translate(c.dx - 70, c.dy - 70);
      KolamRadarPainter(
        progress: 0.8,
        color: AppColors.inkFor(dark),
      ).paint(canvas, const Size(140, 140));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_FakeMap old) => false;
}

void main() {
  final out = Platform.environment['PLAN_D_SHOTS'];

  const driver = AssignedDriver(
    name: 'Rahul Patil',
    rating: 4.9,
    vehicleMake: 'Bajaj',
    vehicleModel: 'RE',
    vehicleColor: 'Yellow',
    plate: 'MH12AB3456',
    phone: '+919876543210',
    etaSec: 60,
  );
  const breakdown = FareBreakdown(
    baseFare: 30,
    distanceFare: 48,
    timeFare: 14,
    bookingFee: 10,
  );
  final estimate = TripEstimate(
    distanceM: 4200,
    durationS: 900,
    polyline: '',
    surge: 1,
    currency: 'INR',
    pickup: const GeoPoint(18.519, 73.855),
    dropoff: const GeoPoint(18.53, 73.87),
    tiers: const [
      FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 102,
        currency: 'INR',
        etaSeconds: 180,
        breakdown: breakdown,
      ),
      FareTier(
        tier: 'comfort',
        label: 'Comfort',
        capacity: 4,
        fare: 140,
        currency: 'INR',
        etaSeconds: 300,
        breakdown: breakdown,
      ),
      FareTier(
        tier: 'xl',
        label: 'XL',
        capacity: 6,
        fare: 190,
        currency: 'INR',
        etaSeconds: 420,
      ),
      // Auto and bike are not tiers yet (another change adds them to the
      // backend); they are here to show D's list leading with them.
      FareTier(
        tier: 'auto',
        label: 'Auto',
        capacity: 3,
        fare: 64,
        currency: 'INR',
        etaSeconds: 120,
        breakdown: breakdown,
      ),
      FareTier(
        tier: 'bike',
        label: 'Bike',
        capacity: 1,
        fare: 38,
        currency: 'INR',
        etaSeconds: 90,
      ),
    ],
  );
  final trip = Trip(
    id: 't1',
    status: TripStatus.accepted,
    tier: 'economy',
    startOtp: '4827',
    paymentMode: 'cash',
    currency: 'INR',
    fareEstimate: 102,
    pickup: const TripEndpoint(
      point: GeoPoint(18.519, 73.855),
      address: 'Shaniwar Wada, Pune',
    ),
    dropoff: const TripEndpoint(
      point: GeoPoint(18.53, 73.87),
      address: 'Koregaon Park, Pune',
    ),
  );
  final base = TripState(
    trip: trip,
    driver: driver,
    paymentMode: 'cash',
    pickupAddr: 'Shaniwar Wada, Pune',
    dropoffAddr: 'Koregaon Park, Pune',
  );

  final shots = <String, TripState>{
    'where-to': const TripState(phase: TripPhase.idle),
    'choose-ride': base.copyWith(
      phase: TripPhase.choosingRide,
      estimate: estimate,
      selectedTier: 'auto',
    ),
    'finding-driver': base.copyWith(
      phase: TripPhase.searching,
      estimate: estimate,
      selectedTier: 'economy',
    ),
    'arrived': base.copyWith(phase: TripPhase.driverArrived),
    'completed': base.copyWith(
      phase: TripPhase.completed,
      fareFinal: 102.0,
      receipt: const Receipt(
        tripId: 't1',
        fare: 102,
        currency: 'INR',
        method: 'cash',
      ),
    ),
  };
  const saved = [
    SavedPlace(
      id: 'h',
      label: 'Home',
      point: GeoPoint(18.52, 73.85),
      address: 'Deccan Gymkhana, Pune',
    ),
    SavedPlace(
      id: 'w',
      label: 'Work',
      point: GeoPoint(18.55, 73.9),
      address: 'EON IT Park, Kharadi',
    ),
  ];

  const phone = Size(390, 844);

  Future<GlobalKey> pump(
    WidgetTester tester,
    TripState state, {
    required bool dark,
    required bool withFonts,
  }) async {
    tester.view.physicalSize = phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    AppColors.syncBrightness(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => AppColors.syncBrightness(Brightness.light));
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: phone,
              padding: EdgeInsets.only(top: 47, bottom: 34),
              // The shot is a still: the finished kolam, the popped check.
              disableAnimations: true,
            ),
            child: Scaffold(
              body: BlocProvider<TripCubit>.value(
                value: cubit,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _FakeMap(
                          dark: dark,
                          kolam: state.phase == TripPhase.searching,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: RideSheetForPhase(
                        state: state,
                        onSearch: () {},
                        onPickSaved: (_) {},
                        savedPlaces: state.phase == TripPhase.idle
                            ? saved
                            : const [],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (withFonts) {
      // Decode the vehicle art for real so it appears in the shot.
      await tester.runAsync(() async {
        for (final e in find.byType(Image).evaluate()) {
          final img = e.widget as Image;
          await precacheImage(img.image, e);
        }
      });
      await tester.pump(const Duration(milliseconds: 50));
    }
    return key;
  }

  for (final MapEntry(key: name, value: state) in shots.entries) {
    for (final dark in [false, true]) {
      testWidgets('$name (${dark ? 'dark' : 'light'})', (tester) async {
        if (out != null) await tester.runAsync(_loadFonts);
        final key = await pump(
          tester,
          state,
          dark: dark,
          withFonts: out != null,
        );
        expect(tester.takeException(), isNull);

        if (AppVariant.local) {
          switch (name) {
            case 'where-to':
              expect(find.byType(LocalCityscape), findsOneWidget);
            case 'choose-ride':
              expect(
                find.bySemanticsLabel('Fare details for Auto'),
                findsOneWidget,
              );
              // Order comes from the server (cheapest first: bike, auto,
              // cars), the same in every look.
              expect(find.text('Auto'), findsOneWidget);
            case 'finding-driver':
              expect(find.byType(PulseRadar), findsOneWidget);
            case 'arrived':
            case 'completed':
              expect(find.byType(PayDriverStrip), findsOneWidget);
              expect(
                find.bySemanticsLabel(
                  RegExp(r'^Pay ₹102 to Rahul: cash or UPI$'),
                ),
                findsOneWidget,
              );
          }
        } else {
          expect(find.byType(LocalCityscape), findsNothing);
          expect(find.byType(PayDriverStrip), findsNothing);
        }

        if (out == null) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(out).createSync(recursive: true);
          File(
            '$out/$name-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      });
    }
  }
}
