import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:driver_app/features/trip_extras/trip_extras.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

const _fontDir = '../../packages/design_system/fonts';
const _out = String.fromEnvironment('DRV_TRIP_PNG_DIR');

Future<void> _loadFonts() async {
  final dir = Directory(_fontDir);
  final byFamily = <String, List<File>>{};
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.ttf')) continue;
    if (name.startsWith('Phosphor') && name != 'Phosphor-Regular.ttf') continue;
    final family = name.split('-').first;
    byFamily.putIfAbsent(family, () => []).add(f);
  }
  for (final e in byFamily.entries) {
    final fam = e.key == 'Phosphor' ? 'PhosphorRegular' : e.key;
    for (final name in [fam, 'packages/design_system/$fam']) {
      final loader = FontLoader(name);
      for (final f in e.value) {
        loader.addFont(f.readAsBytes().then((b) => b.buffer.asByteData()));
      }
      await loader.load();
    }
  }
}

final _trip = Trip(
  id: 't1',
  status: TripStatus.inProgress,
  tier: 'comfort',
  pickup: const TripEndpoint(
      point: GeoPoint(18.52, 73.85), address: 'Central Station, Gate 2'),
  dropoff: const TripEndpoint(
      point: GeoPoint(18.56, 73.91), address: 'Riverside Business Park, Tower B'),
  stops: const [
    TripStop(point: GeoPoint(18.53, 73.87), address: 'City Library'),
  ],
  riderName: 'Aisha Karimova',
  pickupNote: 'Blue jacket, by the ticket office',
  distanceM: 8200,
  durationS: 1260,
  fareEstimate: 240,
  paymentMode: 'cash',
);

Future<void> _pump(WidgetTester t, Widget child, String name) async {
  t.view.physicalSize = const Size(360 * 2, 2000 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: const MediaQueryData(
          size: Size(360, 2000), textScaler: TextScaler.linear(1.5)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: RepaintBoundary(
            key: const ValueKey('shot'),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: child,
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
  if (_out.isNotEmpty) {
    await t.runAsync(() async {
      final ro = t.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
      final img = await ro.toImage(pixelRatio: 2);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/drv_trip_$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }
}

void main() {
  setUpAll(_loadFonts);

  for (final stage in TripExtrasStage.values) {
    testWidgets('trip extras ${stage.name}: no overflow at 360dp, 1.5x text',
        (t) async {
      await _pump(
        t,
        DriverTripExtras(
          stage: stage,
          trip: _trip,
          remainingMeters: stage == TripExtrasStage.waiting ? null : 3100,
          onNavigate: () {},
          onSafety: () {},
          onShare: () {},
          onMessage: () {},
        ),
        stage.name,
      );
      expect(find.text('Aisha Karimova'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.textContaining('Collect cash'), findsOneWidget);
      expect(find.text('Safety & SOS'), findsOneWidget);
      expect(find.text('Driver tip'), findsOneWidget);
    });
  }

  testWidgets('completed extras: this trip, today, tip', (t) async {
    await _pump(
      t,
      DriverCompletedExtras(
        loadTrip: () async => _trip,
        todayTotal: 1840,
      ),
      'completed',
    );
    expect(find.text('This trip'), findsOneWidget);
    expect(find.text('Today so far'), findsOneWidget);
  });

  testWidgets('pull-up sheet: collapsed shows only the child; drag reveals',
      (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: TripPullUpSheet(
            extras: const Text('EXTRAS'),
            child: const SizedBox(height: 120, child: Text('COLLAPSED')),
          ),
        ),
      ),
    ));
    expect(find.text('COLLAPSED'), findsOneWidget);
    expect(find.text('EXTRAS'), findsNothing);
    await t.drag(find.text('COLLAPSED'), const Offset(0, -200));
    await t.pumpAndSettle();
    expect(find.text('EXTRAS'), findsOneWidget);
    await t.drag(find.text('COLLAPSED'), const Offset(0, 200));
    await t.pumpAndSettle();
    expect(find.text('EXTRAS'), findsNothing);
  });
}
