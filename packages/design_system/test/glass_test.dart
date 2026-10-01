import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plan F "Map Glass". GlassSurface and the plate tag are tested directly in
/// every build; the glass *wiring* (AppSheet, AppCircleButton, AppIconBadge)
/// is only on under `--dart-define=THEME=glass`, so those tests assert glass
/// there and "exactly as before" (no glass) in every other build.
void main() {
  Widget host(Widget child, {bool highContrast = false, bool dark = false}) =>
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            highContrast: highContrast,
          ),
          child: Scaffold(body: Center(child: child)),
        ),
      );

  group('GlassSurface', () {
    testWidgets('blurs what is behind it', (tester) async {
      await tester.pumpWidget(
        host(const GlassSurface(child: SizedBox(width: 200, height: 100))),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('high contrast draws solid: no blur', (tester) async {
      await tester.pumpWidget(
        host(
          const GlassSurface(child: SizedBox(width: 200, height: 100)),
          highContrast: true,
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('presence 0 builds no blur pass at all', (tester) async {
      await tester.pumpWidget(
        host(
          const GlassSurface(
            presence: 0,
            child: SizedBox(width: 200, height: 100),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  test('glass tokens match Plan F', () {
    expect(AppGlass.fill(false), const Color(0xB8FFFFFF)); // 72 %
    expect(AppGlass.fill(true), const Color(0xB312161A)); // 70 %
    expect(AppGlass.fillStrong(false), const Color(0xD6FFFFFF)); // 84 %
    expect(AppGlass.fillStrong(true), const Color(0xD112161A)); // 82 %
    expect(AppGlass.blurSigma, 24);
    expect(AppGlass.sheetInset, 12);
    expect(AppGlass.sheetRadius, 28);
  });

  test('brand text on light glass is the deeper blue; elsewhere the ink', () {
    if (AppColors.glass) {
      expect(AppColors.accentTextFor(false), const Color(0xFF1740B0));
    } else {
      expect(AppColors.accentTextFor(false), AppColors.inkFor(false));
    }
    expect(AppColors.accentTextFor(true), AppColors.inkFor(true));
  });

  test('the sheet spring starts at 0, ends at 1 and barely overshoots', () {
    const c = GlassSpringCurve();
    expect(c.transform(0), 0);
    expect(c.transform(1), 1);
    var peak = 0.0;
    for (var i = 1; i < 100; i++) {
      final v = c.transform(i / 100);
      if (v > peak) peak = v;
    }
    expect(peak, greaterThan(1)); // it is a spring…
    expect(peak, lessThan(1.05)); // …not a bounce
  });

  testWidgets('the plate tag renders the plate under a transparent gap', (
    tester,
  ) async {
    final tag = await tester.runAsync(
      () => AppMap.renderPlateTag('MH 12 AB 1234'),
    );
    expect(tag, isNotNull);
    expect(tag!.size.height, greaterThan(AppMap.plateTagGap + 10));
    expect(tag.size.width, greaterThan(40));
    final image = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(tag.png);
      return (await codec.getNextFrame()).image;
    });
    // Rasterised at 3x the logical size.
    expect(image!.width, (tag.size.width * 3).ceil());
    // The band above the chip is empty, so the car shows through it.
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    int alphaAt(int x, int y) =>
        bytes!.getUint8((y * image.width + x) * 4 + 3);
    expect(alphaAt(image.width ~/ 2, 5), 0);
    // …and the chip itself is opaque (solid, never glass).
    final chipY = ((AppMap.plateTagGap + 4 + 3) * 3).round();
    expect(alphaAt(image.width ~/ 2, chipY), 255);
  });

  testWidgets('AppSheet: a floating glass card only in the glass build', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: AppSheet(child: const SizedBox(height: 120)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final glass = find.byType(GlassSurface);
    if (!AppGlass.enabled) {
      expect(glass, findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      return;
    }
    expect(glass, findsOneWidget);
    final r = tester.getRect(glass);
    expect(r.left, AppGlass.sheetInset);
    expect(r.right, 400 - AppGlass.sheetInset);
    expect(r.bottom, 800 - AppGlass.sheetInset);
  });

  testWidgets('AppSheet (glass): the handle toggles when it has a job', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AppSheet(
              onHandleTap: () => taps++,
              handleLabel: 'Show more',
              child: const SizedBox(height: 120),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Every build: a handle with a job is a button (draggable sheets).
    final handle = find.bySemanticsLabel('Show more');
    await tester.tap(handle);
    expect(taps, 1);
  });

  testWidgets('map buttons and icon badges go glass only in the glass build', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppCircleButton(icon: PhosphorIconsRegular.list, onPressed: () {}),
            const AppIconBadge(icon: PhosphorIconsRegular.house),
          ],
        ),
      ),
    );
    expect(
      find.byType(GlassSurface),
      AppGlass.enabled ? findsOneWidget : findsNothing,
    );
    final badge = find.descendant(
      of: find.byType(AppIconBadge),
      matching: find.byType(CustomPaint),
    );
    expect(badge, AppGlass.enabled ? findsWidgets : findsNothing);
  });
}
