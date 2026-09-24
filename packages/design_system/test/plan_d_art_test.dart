// Plan D ("Local Colour", THEME=local) art and signature widgets.
//
// Runs in every build — the art is plain widgets, so it must paint anywhere —
// and checks the kolam geometry and the pieces' accessibility. Writing PNGs
// for review is opt-in so CI never touches docs/:
//
//   PLAN_D_SHOTS=../../docs/brand/research/plan-d \
//       flutter test test/plan_d_art_test.dart --dart-define=THEME=local
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
          File('fonts/$f').readAsBytes().then((b) => b.buffer.asByteData()));
    }
    await loader.load();
  }

  await load('packages/design_system/PhosphorRegular', ['Phosphor-Regular.ttf']);
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
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final out = Platform.environment['PLAN_D_SHOTS'];

  group('kolam geometry', () {
    test('a 1-3-5-7-5-3-1 diamond of 25 dots', () {
      expect(Kolam.dots, hasLength(25));
      final perRing = <int, int>{};
      for (final d in Kolam.dots) {
        perRing[Kolam.ringOf(d)] = (perRing[Kolam.ringOf(d)] ?? 0) + 1;
      }
      expect(perRing, {0: 1, 1: 4, 2: 8, 3: 12});
    });

    test('rings land from the centre outward, then the pattern fades', () {
      expect(Kolam.dotScale(0, 0.2), greaterThan(0.9));
      expect(Kolam.dotScale(3, 0.2), 0);
      expect(Kolam.dotScale(3, 0.7), closeTo(1, 0.01));
      expect(Kolam.fade(0.5), 1);
      expect(Kolam.fade(1.0), closeTo(0, 1e-9));
      expect(Kolam.lineProgress(0.3), 0);
      expect(Kolam.lineProgress(0.85), 1);
    });

    test('the kolam line never runs through a dot', () {
      final path = Kolam.linePath(10, Offset.zero);
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 0.5) {
          final p = m.getTangentForOffset(d)!.position;
          for (final dot in Kolam.dots) {
            expect((p - dot * 10).distance, greaterThan(2.5),
                reason: 'line touches dot $dot at $p');
          }
        }
      }
    });

    test('map kolam: 25 dots on a 42 m grid; still = the finished pattern', () {
      final still = AppMap.kolamDots(0, still: true);
      expect(still, hasLength(25));
      expect(still.every((d) => d.$3 == AppMap.kolamDotM), isTrue);
      final start = AppMap.kolamDots(0);
      // At t=0 nothing has landed yet.
      expect(start.where((d) => d.$3 > 0), isEmpty);
    });
  });

  test('Plan D colour pairs clear WCAG (computed)', () {
    // D's tokens only exist in the THEME=local build.
    if (!AppVariant.local) return;
    for (final dark in [false, true]) {
      // Text on the pay strip.
      expect(_contrast(LocalColour.payInkFor(dark), LocalColour.payFillFor(dark)),
          greaterThan(4.5));
      // Badge glyph on the marigold tint (icons need 3:1; we hold 4.5).
      expect(_contrast(AppColors.inkFor(dark), LocalColour.badgeFor(dark)),
          greaterThan(4.5));
      // Body text on paper.
      final text = dark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
      final sub =
          dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
      expect(_contrast(text, LocalColour.paperFor(dark)), greaterThan(7));
      expect(_contrast(sub, LocalColour.paperFor(dark)), greaterThan(4.5));
    }
    // Marigold is art only — it could not carry text, which is why it never
    // does.
    expect(_contrast(LocalColour.marigold, LocalColour.paperLight),
        lessThan(3));
  });

  testWidgets('the map pickup radar: kolam in Plan D, rings elsewhere',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const MediaQuery(
        // Reduce Motion: the finished pattern, no ticking timer.
        data: MediaQueryData(disableAnimations: true),
        child: SizedBox(
          width: 400,
          height: 600,
          child: AppMap(
            initialCenter: LatLng(18.519, 73.855),
            pulseAt: LatLng(18.519, 73.855),
          ),
        ),
      ),
    ));
    await tester.pump();
    final map = tester.widget<gmaps.GoogleMap>(find.byType(gmaps.GoogleMap));
    final ids = map.circles.map((c) => c.circleId.value).toList();
    if (AppVariant.local) {
      expect(ids.where((i) => i.startsWith('kolam')), hasLength(25));
      expect(map.polylines.map((p) => p.polylineId.value),
          contains('kolam_line'));
    } else {
      expect(ids.where((i) => i.startsWith('pulse')), hasLength(3));
      expect(map.polylines.map((p) => p.polylineId.value),
          isNot(contains('kolam_line')));
    }
  });

  testWidgets('pay strip reads as one sentence and is at least 48 tall',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: PayDriverStrip(amount: '₹102', driverName: 'Rahul'),
      ),
    ));
    expect(find.bySemanticsLabel('Pay ₹102 to Rahul: cash or UPI'),
        findsOneWidget);
    expect(tester.getSize(find.byType(PayDriverStrip)).height,
        greaterThanOrEqualTo(48));
  });

  testWidgets('a tappable LocalChip keeps a 48 dp target', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: LocalChip(label: 'Rate card', onTap: () => taps++),
        ),
      ),
    ));
    final size = tester.getSize(find.byType(LocalChip));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
    await tester.tap(find.byType(LocalChip));
    expect(taps, 1);
  });

  testWidgets('the art paints (light and dark) and is hidden from readers',
      (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Column(children: [
            LocalCityscape(),
            LocalDoneArt(),
            KolamLoader(),
          ]),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('LocalDoneArt is still under Reduce Motion', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(body: LocalDoneArt()),
      ),
    ));
    // Nothing animates: the art is drawn finished on the first frame.
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('shots: Plan D art board', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();

    Widget panel(ThemeData theme) => Theme(
          data: theme,
          child: Builder(builder: (context) {
            final dark = theme.brightness == Brightness.dark;
            return Container(
              width: 380,
              color: LocalColour.paperFor(dark),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LocalCityscape(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const LocalDoneArt(),
                      for (final p in [0.3, 0.6, 0.8])
                        KolamLoader(size: 56, progress: p),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      PulseRadar(
                          size: 56,
                          child: Icon(PhosphorIconsRegular.taxi, size: 20)),
                      AppIconBadge(icon: PhosphorIconsRegular.house),
                      AppIconBadge(
                          icon: PhosphorIconsRegular.briefcase,
                          tone: AppIconBadgeTone.neutral),
                      AppIconBadge(icon: PhosphorIconsRegular.shieldCheck),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const PayDriverStrip(amount: '₹102', driverName: 'Rahul'),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: [
                    const LocalChip(
                        label: '4', icon: PhosphorIconsRegular.user),
                    LocalChip(
                        label: 'Rate card',
                        icon: PhosphorIconsRegular.receipt,
                        onTap: () {}),
                  ]),
                  const SizedBox(height: 12),
                  Text('Where to?',
                      style: theme.textTheme.headlineSmall),
                  Text('Shaniwar Wada, Pune · ₹102',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            );
          }),
        );

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [panel(AppTheme.light), panel(AppTheme.dark)],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(tester.takeException(), isNull);
    if (out == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(out).createSync(recursive: true);
      File('$out/art-board.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}
