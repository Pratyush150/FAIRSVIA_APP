import 'dart:io';
import 'dart:ui' as ui;

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/features/home_extras/driver_home_extras.dart';
import 'package:driver_app/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fonts = '../../packages/design_system/fonts';
const _out = String.fromEnvironment('DRV_SHOTS');

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
          File('$_fonts/$f').readAsBytes().then((b) => b.buffer.asByteData()));
    }
    await loader.load();
  }

  await load('packages/design_system/PhosphorRegular', ['Phosphor-Regular.ttf']);
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
  await load('Roboto', ['Inter-Regular.ttf', 'Inter-Medium.ttf']);
}

/// The offline / online driver sheets pulled up: real sections under the
/// compact view, nothing overflowing at 360 dp with 1.5x text.
void main() {
  setUpAll(_loadFonts);

  Future<void> pump(
    WidgetTester tester, {
    required bool expanded,
    double textScale = 1.0,
    bool online = false,
    GlobalKey? boundary,
  }) async {
    const size = Size(360, 780);
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            backgroundColor: const Color(0xFFDDE3E6),
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Builder(
                builder: (context) => DriverExpandableSheet(
                  initiallyExpanded: expanded,
                  extras: [
                    DriverTodaySection(
                      load: () async => const DriverEarnings(
                          total: 1840,
                          trips: 7,
                          range: 'today',
                          onlineSeconds: 5 * 3600 + 20 * 60),
                      onOpen: () {},
                    ),
                    const DriverBusyAreasSection(
                      cells: [
                        DemandCell(
                            lat: 18.52, lng: 73.86, count: 9, intensity: 0.9),
                        DemandCell(
                            lat: 18.53, lng: 73.87, count: 4, intensity: 0.4),
                      ],
                      from: LatLng(18.51, 73.85),
                    ),
                    DriverExtraSection(
                      title: 'Tips for drivers',
                      child: DriverPosterCarousel(
                          posters: driverTipPosters(context, onQuests: () {})),
                    ),
                  ],
                  child: online
                      ? const Text("You're online")
                      : DriverOfflineSheet(
                          lastEarned: 1840, onGoOnline: () {}),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
    if (_out.isEmpty) return;
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('collapsed: compact view only, no extras', (tester) async {
    await pump(tester, expanded: false);
    expect(find.text("You're offline"), findsOneWidget);
    expect(find.text('Busy areas nearby'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the handle pulls the sheet up', (tester) async {
    await pump(tester, expanded: false);
    await tester.tap(find.bySemanticsLabel('Expand'));
    await tester.pumpAndSettle();
    expect(find.text('Busy areas nearby'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('dragging up expands, dragging down collapses', (tester) async {
    await pump(tester, expanded: false);
    await tester.fling(find.text("You're offline"), const Offset(0, -300), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Busy areas nearby'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Collapse'));
    await tester.pumpAndSettle();
    expect(find.text('Busy areas nearby'), findsNothing);
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('expanded offline sheet at ${scale}x text: real figures, '
        'no overflow', (tester) async {
      final key = GlobalKey();
      await pump(tester, expanded: true, textScale: scale, boundary: key);
      expect(tester.takeException(), isNull);
      expect(find.text('7'), findsOneWidget); // trips today
      expect(find.text('5h 20m'), findsOneWidget);
      expect(find.text('Very busy area'), findsOneWidget);
      expect(find.text('Complete quests for bonuses'), findsOneWidget);
      await shot(tester, key, 'drv_offline_expanded_${scale}x');
    });
  }

  testWidgets('expanded online sheet renders', (tester) async {
    final key = GlobalKey();
    await pump(tester, expanded: true, online: true, boundary: key);
    expect(tester.takeException(), isNull);
    await shot(tester, key, 'drv_online_expanded');
  });

  testWidgets('poster tap opens its explainer', (tester) async {
    await pump(tester, expanded: true);
    await tester.ensureVisible(find.byType(PageView));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a break — safety first'));
    await tester.pumpAndSettle();
    expect(find.text('Breaks and online time'), findsOneWidget);
  });
}
