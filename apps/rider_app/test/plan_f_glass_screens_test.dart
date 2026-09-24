import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
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

/// Plan F "Map Glass" (`--dart-define=THEME=glass`): the rider's map screen
/// with the floating glass sheet over a *painted stand-in* for the map
/// (GoogleMap is a platform view and does not render in widget tests), the
/// top map buttons, and — for live phases — the top-down car with the plate
/// tag that AppMap would place on the real map.
///
/// The assertions run in every build: in the glass build the sheet is glass
/// and floats; in every other build no glass is drawn at all.
///
/// Screenshots: set PLAN_F_SHOTS to a directory (only then are PNGs written):
///
///   PLAN_F_SHOTS=../../docs/brand/research/plan-f \
///     flutter test --dart-define=THEME=glass test/plan_f_glass_screens_test.dart
void main() {
  final shots = Platform.environment['PLAN_F_SHOTS'];

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
  const saved = [
    SavedPlace(
      id: 'h',
      label: 'Home',
      point: GeoPoint(18.51, 73.84),
      address: 'Prabhat Road, Erandwane, Pune',
    ),
    SavedPlace(
      id: 'w',
      label: 'Work',
      point: GeoPoint(18.55, 73.90),
      address: 'EON IT Park, Kharadi, Pune',
    ),
  ];

  // Loaded once: fonts for readable screenshots, the car art and plate tag.
  ui.Image? car;
  ui.Image? plate;
  setUpAll(() async {
    await _loadFonts();
    final carBytes = File(
      '${Directory.current.path}/../../packages/design_system/assets/vehicles/top/economy.png',
    ).readAsBytesSync();
    car = await _decode(carBytes);
    // As home_page passes it: formatted like the driver card's plate.
    final tag =
        await AppMap.renderPlateTag(Market.current.formatPlate(driver.plate!));
    plate = await _decode(tag.png);
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    TripState state, {
    bool dark = false,
    bool highContrast = false,
    bool reduceMotion = false,
    bool showCar = false,
    bool recenter = false,
    List<SavedPlace> savedPlaces = const [],
    GlobalKey? boundary,
  }) async {
    const size = Size(411, 914);
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    AppColors.syncBrightness(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => AppColors.syncBrightness(Brightness.light));
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            highContrast: highContrast,
            disableAnimations: reduceMotion,
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
                        painter: _FakeMapPainter(
                          dark: dark,
                          route: state.phase != TripPhase.idle,
                          car: showCar ? car : null,
                          plate: showCar ? plate : null,
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppCircleButton(
                                icon: PhosphorIconsRegular.list,
                                tooltip: 'Account menu',
                                onPressed: () {},
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              AppCircleButton(
                                icon: PhosphorIconsRegular.gpsFix,
                                tooltip: 'Recenter',
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: RecenterPill(
                              visible: recenter,
                              onPressed: () {},
                            ),
                          ),
                          Flexible(
                            child: RideSheetForPhase(
                              state: state,
                              onSearch: () {},
                              savedPlaces: savedPlaces,
                              onPickSaved: (_) {},
                            ),
                          ),
                        ],
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
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  // Glass build: plan_f_*.png. Any other build writes the same screens as
  // compare_<variant>_*.png, for a side-by-side with the solid sheet.
  final prefix = AppGlass.enabled
      ? 'plan_f'
      : 'compare_${AppColors.variant.isEmpty ? 'default' : AppColors.variant}';

  Future<void> shoot(WidgetTester tester, GlobalKey key, String name) async {
    if (shots == null) return;
    name = name.replaceFirst('plan_f', prefix);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(shots).createSync(recursive: true);
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  final screens =
      <
        String,
        ({TripState state, bool car, bool recenter, List<SavedPlace> saved})
      >{
        'home': (
          state: const TripState(),
          car: false,
          recenter: false,
          saved: saved,
        ),
        'choose_ride': (
          state: base.copyWith(
            phase: TripPhase.choosingRide,
            estimate: estimate,
            selectedTier: 'economy',
          ),
          car: false,
          recenter: false,
          saved: const [],
        ),
        'driver_en_route': (
          state: base.copyWith(phase: TripPhase.driverEnRoute),
          car: true,
          recenter: false,
          saved: const [],
        ),
        'on_trip': (
          state: base.copyWith(phase: TripPhase.onTrip, estimate: estimate),
          car: true,
          recenter: true,
          saved: const [],
        ),
      };

  for (final MapEntry(key: name, value: s) in screens.entries) {
    for (final dark in const [false, true]) {
      final label = '${name}_${dark ? 'dark' : 'light'}';
      testWidgets('Plan F screen: $label', (tester) async {
        final key = GlobalKey();
        await pumpScreen(
          tester,
          s.state,
          dark: dark,
          showCar: s.car,
          recenter: s.recenter,
          savedPlaces: s.saved,
          boundary: key,
        );
        expect(tester.takeException(), isNull);
        final blur = find.byType(BackdropFilter);
        if (AppGlass.enabled) {
          expect(blur, findsWidgets, reason: 'glass build draws glass');
        } else {
          expect(blur, findsNothing, reason: 'other builds stay solid');
        }
        await shoot(tester, key, 'plan_f_$label');
      });
    }
  }

  testWidgets('Plan F: the live card opens compact and the handle expands it', (
    tester,
  ) async {
    final key = GlobalKey();
    await pumpScreen(
      tester,
      base.copyWith(phase: TripPhase.driverEnRoute),
      showCar: true,
      boundary: key,
    );
    final sheet = find.byType(AppSheet);
    final compact = tester.getSize(sheet).height;
    if (!AppGlass.enabled) {
      // Other builds: no compact mode, no handle button.
      expect(find.bySemanticsLabel('Show more ride details'), findsNothing);
      return;
    }
    // Compact: at most the compact share of the screen (+ the bottom gap).
    expect(compact, lessThanOrEqualTo(914 * kGlassCompactFraction + 25));
    // Floats: inset from both screen edges.
    final rect = tester.getRect(find.byType(GlassSurface).last);
    expect(rect.left, AppGlass.sheetInset);
    expect(rect.right, 411 - AppGlass.sheetInset);
    await tester.tap(find.bySemanticsLabel('Show more ride details'));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getSize(sheet).height, greaterThan(compact + 100));
    expect(tester.takeException(), isNull);
    await shoot(tester, key, 'plan_f_driver_en_route_expanded_light');
    // …and back.
    await tester.tap(find.bySemanticsLabel('Show less'));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getSize(sheet).height, closeTo(compact, 1));
  });

  testWidgets('Plan F: home has no sheet — the Where-to pill floats alone', (
    tester,
  ) async {
    await pumpScreen(tester, const TripState(), savedPlaces: saved);
    if (!AppGlass.enabled) return;
    // Two glass pieces in the sheet (pill + saved places), none behind them.
    final pill = tester.getRect(find.bySemanticsLabel('Where to?'));
    expect(pill.left, greaterThanOrEqualTo(AppGlass.sheetInset));
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('EON IT Park, Kharadi, Pune'), findsOneWidget);
    // The pill comes before the saved places, as in every build.
    expect(pill.top, lessThan(tester.getRect(find.text('Home')).top));
  });

  testWidgets('Plan F: high contrast draws solid — no blur anywhere', (
    tester,
  ) async {
    final key = GlobalKey();
    await pumpScreen(
      tester,
      base.copyWith(phase: TripPhase.driverEnRoute),
      highContrast: true,
      showCar: true,
      boundary: key,
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
    await shoot(tester, key, 'plan_f_driver_en_route_high_contrast');
  });

  testWidgets('Plan F: Reduce Motion — the sheet snaps to its new size', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      base.copyWith(phase: TripPhase.driverEnRoute),
      reduceMotion: true,
    );
    final sizes = find.descendant(
      of: find.byType(AppSheet),
      matching: find.byType(AnimatedSize),
    );
    if (AppGlass.enabled) {
      // No spring at all: the card takes its size at once.
      expect(sizes, findsNothing);
    } else {
      expect(tester.widget<AnimatedSize>(sizes.first).duration, Duration.zero);
    }
  });
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

final String _flutterRoot =
    Platform.environment['FLUTTER_ROOT'] ??
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;

Future<void> _loadFonts() async {
  final fonts = Directory(
    '${Directory.current.path}/../../packages/design_system/fonts',
  ).resolveSymbolicLinksSync();
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(File(p).readAsBytes().then((b) => b.buffer.asByteData()));
    }
    await loader.load();
  }

  await load('MaterialIcons', [
    '$_flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  await load('packages/design_system/PhosphorRegular', [
    '$fonts/Phosphor-Regular.ttf',
  ]);
  await load('packages/design_system/PhosphorFill', [
    '$fonts/Phosphor-Fill.ttf',
  ]);
  await load('packages/design_system/Inter', [
    '$fonts/Inter-Regular.ttf',
    '$fonts/Inter-Medium.ttf',
    '$fonts/Inter-SemiBold.ttf',
    '$fonts/Inter-Bold.ttf',
    '$fonts/Inter-ExtraBold.ttf',
  ]);
}

/// A stand-in for the desaturated Plan F basemap: city blocks, a river,
/// parks, a road grid with two arterials, a few place labels, and (for a
/// booked ride) the teal route with its glow, the pickup/drop pins and the
/// car with its plate tag — so the glass has something real to show through.
class _FakeMapPainter extends CustomPainter {
  _FakeMapPainter({
    required this.dark,
    required this.route,
    this.car,
    this.plate,
  });

  final bool dark;
  final bool route;
  final ui.Image? car;
  final ui.Image? plate;

  @override
  void paint(Canvas canvas, Size size) {
    final land = dark ? const Color(0xFF1B2024) : const Color(0xFFEDEEEA);
    final block = dark ? const Color(0xFF22282D) : const Color(0xFFE3E5E0);
    final park = dark ? const Color(0xFF1C2B24) : const Color(0xFFCFE6CF);
    final water = dark ? const Color(0xFF0E2433) : const Color(0xFFAFD3EA);
    final road = dark ? const Color(0xFF30383F) : const Color(0xFFFFFFFF);
    final casing = dark ? const Color(0xFF151A1E) : const Color(0xFFD5D8D3);
    final artery = dark ? const Color(0xFF4A4436) : const Color(0xFFFBE7A6);
    final label = dark ? const Color(0xFF8A96A0) : const Color(0xFF6B7780);

    canvas.drawRect(Offset.zero & size, Paint()..color = land);
    final rnd = math.Random(7);
    // Blocks on a slightly rotated grid.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.21);
    canvas.translate(-size.width, -size.height);
    const step = 74.0;
    for (var x = 0.0; x < size.width * 2; x += step) {
      for (var y = 0.0; y < size.height * 2; y += step) {
        final r = Rect.fromLTWH(x + 7, y + 7, step - 14, step - 14);
        final roll = rnd.nextDouble();
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(3)),
          Paint()..color = roll < 0.12 ? park : block,
        );
      }
    }
    // Road grid with casings.
    final casingPaint = Paint()
      ..color = casing
      ..strokeWidth = 9;
    final roadPaint = Paint()
      ..color = road
      ..strokeWidth = 7;
    for (var x = 0.0; x < size.width * 2; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height * 2), casingPaint);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height * 2), roadPaint);
    }
    for (var y = 0.0; y < size.height * 2; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width * 2, y), casingPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width * 2, y), roadPaint);
    }
    final art = Paint()
      ..color = artery
      ..strokeWidth = 11;
    canvas.drawLine(
      Offset(step * 6, 0),
      Offset(step * 6, size.height * 2),
      art,
    );
    canvas.drawLine(
      Offset(0, step * 13),
      Offset(size.width * 2, step * 13),
      art,
    );
    canvas.restore();

    // River.
    final river = Path()
      ..moveTo(-20, size.height * 0.30)
      ..cubicTo(
        size.width * 0.3,
        size.height * 0.22,
        size.width * 0.55,
        size.height * 0.46,
        size.width + 20,
        size.height * 0.38,
      );
    canvas.drawPath(
      river,
      Paint()
        ..color = water
        ..style = PaintingStyle.stroke
        ..strokeWidth = 34
        ..strokeCap = StrokeCap.round,
    );

    void text(
      String s,
      Offset at, {
      double sz = 11,
      FontWeight w = FontWeight.w600,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontFamily: 'packages/design_system/Inter',
            fontSize: sz,
            fontWeight: w,
            color: label,
            letterSpacing: 0.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at);
    }

    text('SHIVAJINAGAR', Offset(size.width * 0.08, size.height * 0.16));
    text('DECCAN GYMKHANA', Offset(size.width * 0.46, size.height * 0.53));
    text(
      'Mula-Mutha River',
      Offset(size.width * 0.12, size.height * 0.285),
      sz: 10,
      w: FontWeight.w500,
    );
    text('KOREGAON PARK', Offset(size.width * 0.55, size.height * 0.2));
    text(
      'FC Road',
      Offset(size.width * 0.20, size.height * 0.66),
      sz: 10,
      w: FontWeight.w500,
    );

    if (!route) return;
    // Teal route with a soft glow (Plan F: "teal route with a glow").
    final teal = AppColors.highlightFor(dark);
    final pickup = Offset(size.width * 0.24, size.height * 0.62);
    final drop = Offset(size.width * 0.74, size.height * 0.14);
    final path = Path()
      ..moveTo(pickup.dx, pickup.dy)
      ..lineTo(size.width * 0.24, size.height * 0.46)
      ..lineTo(size.width * 0.55, size.height * 0.40)
      ..lineTo(size.width * 0.60, size.height * 0.24)
      ..lineTo(drop.dx, drop.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = teal.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    // Pickup ring, drop square (the app's stop pins).
    canvas.drawCircle(pickup, 10, Paint()..color = Colors.white);
    canvas.drawCircle(pickup, 8, Paint()..color = Colors.black);
    canvas.drawCircle(pickup, 3, Paint()..color = Colors.white);
    canvas.drawRect(
      Rect.fromCenter(center: drop, width: 20, height: 20),
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      Rect.fromCenter(center: drop, width: 16, height: 16),
      Paint()..color = Colors.black,
    );
    canvas.drawRect(
      Rect.fromCenter(center: drop, width: 5, height: 5),
      Paint()..color = Colors.white,
    );

    final c = car;
    if (c != null) {
      // The car on the route, heading along it, as AppMap draws it
      // (AppMap.carMarkerWidth wide), with the plate tag hung under it.
      final at = Offset(size.width * 0.24, size.height * 0.50);
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(0); // heading north along this leg
      const w = AppMap.carMarkerWidth;
      canvas.drawImageRect(
        c,
        Rect.fromLTWH(0, 0, c.width.toDouble(), c.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: w, height: w),
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
      final p = plate;
      if (p != null) {
        // renderPlateTag rasterises at 3x; the marker's anchor is its
        // top-centre on the car's position.
        final pw = p.width / 3, ph = p.height / 3;
        canvas.drawImageRect(
          p,
          Rect.fromLTWH(0, 0, p.width.toDouble(), p.height.toDouble()),
          Rect.fromLTWH(at.dx - pw / 2, at.dy, pw, ph),
          Paint()..filterQuality = FilterQuality.high,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_FakeMapPainter old) => false;
}
