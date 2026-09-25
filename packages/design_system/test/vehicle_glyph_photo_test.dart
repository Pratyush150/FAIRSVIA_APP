import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ride list's vehicle pictures must be whole: the owner saw the cars
/// "cut" because the square renders were shown with BoxFit.cover in a 16:10
/// slot. These tests pin the fix: contain-fit, and art whose subject sits
/// fully inside its canvas with a transparent margin.
void main() {
  const tiers = ['economy', 'comfort', 'premium', 'xl', 'auto', 'bike', 'driver'];

  testWidgets('vehicle art is shown with BoxFit.contain in a 16:10 box',
      (tester) async {
    for (final tier in tiers) {
      await tester.pumpWidget(MaterialApp(
        home: Center(child: VehicleGlyph(tier: tier, width: 76)),
      ));
      final set = VehicleGlyph.artSet(false);
      if (set == null) continue; // mono: drawn glyph, nothing to crop
      final img = tester.widget<Image>(find.byType(Image));
      expect(img.fit, BoxFit.contain, reason: tier);
      expect(img.width, 76);
      expect(img.height, 76 * 0.625);
      // No clip wraps the picture inside the glyph.
      expect(
          find.descendant(
              of: find.byType(VehicleGlyph), matching: find.byType(ClipRect)),
          findsNothing);
    }
  });

  // Decodes each shipped photo file and checks the vehicle never touches the
  // canvas edge (so nothing is cut), in every resolution and both themes.
  test('photo art: every tier exists, is 16:10 and has a transparent margin',
      () async {
    for (final folder in ['photo', 'photo_dark']) {
      for (final res in ['', '2.0x/', '3.0x/']) {
        for (final tier in tiers) {
          final f = File('assets/vehicles/$folder/$res$tier.webp');
          expect(f.existsSync(), isTrue, reason: f.path);
          expect(f.lengthSync(), lessThan(40 * 1024), reason: '${f.path} size');
          final codec =
              await ui.instantiateImageCodec(f.readAsBytesSync());
          final image = (await codec.getNextFrame()).image;
          expect(image.width * 10, image.height * 16, reason: f.path);
          final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba))!;
          final w = image.width, h = image.height;
          int alpha(int x, int y) => data.getUint8((y * w + x) * 4 + 3);
          var edgeMax = 0;
          for (var x = 0; x < w; x++) {
            edgeMax = [edgeMax, alpha(x, 0), alpha(x, h - 1)]
                .reduce((a, b) => a > b ? a : b);
          }
          for (var y = 0; y < h; y++) {
            edgeMax = [edgeMax, alpha(0, y), alpha(w - 1, y)]
                .reduce((a, b) => a > b ? a : b);
          }
          expect(edgeMax, lessThan(8),
              reason: '${f.path}: subject touches the canvas edge');
          // And there is a real vehicle in it (not an empty canvas).
          var opaque = 0;
          for (var i = 3; i < data.lengthInBytes; i += 4) {
            if (data.getUint8(i) > 200) opaque++;
          }
          expect(opaque, greaterThan(w * h ~/ 10), reason: f.path);
        }
      }
    }
  });

  // Renders the tier column (light + dark) to a PNG for a visual check, when
  // VEHICLE_SHEET_PNG names an output file.
  testWidgets('renders a preview sheet', (tester) async {
    final out = Platform.environment['VEHICLE_SHEET_PNG'];
    if (out == null) return;
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    Widget column(bool dark) => Theme(
          data: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light),
          child: Container(
            width: 150,
            color: dark ? const Color(0xFF151A21) : const Color(0xFFF2F5F7),
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              for (final t in tiers.take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    VehicleGlyph(tier: t, width: 76),
                  ]),
                ),
            ]),
          ),
        );
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [column(false), column(true)]),
          ),
        ),
      ));
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(out).writeAsBytesSync(Uint8List.view(bytes!.buffer));
    });
  });
}
