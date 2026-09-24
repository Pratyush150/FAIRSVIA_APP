// Plan G — "3D Clay" (THEME=clay3d): every Phosphor icon is a colour-bitmap
// glyph from fonts/Phosphor3D.ttf (tool/icons3d/build.py).
//
// Runs in every build. The font tests load the real TTF and render it through
// the engine (FreeType/Skia, the same rasteriser Android uses), so they prove
// the CBDT strike actually draws colour pixels — not just that the file
// exists. The switch tests prove the other builds are untouched.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'icon_inventory_data.dart';

const _family = 'packages/design_system/Phosphor3D';

/// SFNT table tags in [bytes].
Set<String> _tables(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  final n = d.getUint16(4);
  return {
    for (var i = 0; i < n; i++)
      String.fromCharCodes(bytes.sublist(12 + 16 * i, 16 + 16 * i)),
  };
}

/// (opaque pixels, saturated pixels, distinct coarse colours) of an RGBA
/// image. A monochrome glyph tinted one colour has 1–2 coarse colours; a 3D
/// render has shading, so many.
(int, int, int) _stats(ByteData rgba) {
  var opaque = 0, saturated = 0;
  final buckets = <int>{};
  for (var i = 0; i < rgba.lengthInBytes; i += 4) {
    final r = rgba.getUint8(i), g = rgba.getUint8(i + 1), b = rgba.getUint8(i + 2);
    final a = rgba.getUint8(i + 3);
    if (a < 200) continue;
    opaque++;
    final hi = [r, g, b].reduce((x, y) => x > y ? x : y);
    final lo = [r, g, b].reduce((x, y) => x < y ? x : y);
    if (hi - lo > 40) saturated++;
    buckets.add((r >> 5) << 6 | (g >> 5) << 3 | (b >> 5));
  }
  return (opaque, saturated, buckets.length);
}

Future<ByteData> _render(WidgetTester tester, IconData icon,
    {double size = 48, Color color = Colors.black, String family = _family}) async {
  final key = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: key,
        // The glyph from the real font, drawn the way Icon draws it (one
        // character, height 1) — Icon itself needs a const IconData.
        child: Text(
          String.fromCharCode(icon.codePoint),
          style: TextStyle(
              fontFamily: family, fontSize: size, height: 1, color: color),
        ),
      ),
    ),
  ));
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  }))!;
}

void main() {
  group('build switch', () {
    test('Plan G is on only in the clay3d build', () {
      expect(AppClay3D.on, AppColors.variant == 'clay3d');
      expect(AppColors.clay3d, AppClay3D.on);
    });

    test('Regular and Fill resolve to the 3D font only under clay3d', () {
      if (AppClay3D.on) {
        expect(PhosphorIconsRegular.car.fontFamily, 'Phosphor3D');
        expect(PhosphorIconsFill.star.fontFamily, 'Phosphor3D');
        // Code points and package are Phosphor's, so no call site changes.
        expect(PhosphorIconsRegular.car.codePoint, 0xe112);
        expect(PhosphorIconsRegular.car.fontPackage, 'design_system');
        // The ink build's Light weight is its own class, untouched.
        expect(PhosphorIconsLight.car.fontFamily, 'PhosphorLight');
      } else {
        expect(PhosphorIconsRegular.car.fontFamily, isNot('Phosphor3D'));
        expect(PhosphorIconsFill.star.fontFamily, 'PhosphorFill');
      }
    });

    test('hero art paths', () {
      expect(AppClay3D.heroAsset('done', false), 'assets/heroes/clay3d/done.png');
      expect(AppClay3D.heroAsset('done', true),
          'assets/heroes/clay3d_dark/done.png');
      for (final dir in ['clay3d', 'clay3d_dark']) {
        for (final h in ['add_stop', 'prebook', 'done', 'cash']) {
          expect(File('assets/heroes/$dir/$h.png').existsSync(), isTrue,
              reason: '$dir/$h.png');
        }
      }
    });
  });

  group('Phosphor3D font', () {
    final bytes = File('fonts/Phosphor3D.ttf').readAsBytesSync();

    test('carries CBDT/CBLC (Android) and sbix (iOS), and no outlines', () {
      final t = _tables(bytes);
      expect(t, containsAll(['CBDT', 'CBLC', 'sbix', 'cmap', 'hmtx']));
      // A glyf table would make FreeType treat the face as scalable and skip
      // the bitmap strike (the Noto Color Emoji layout has none either).
      expect(t, isNot(contains('glyf')));
    });

    setUpAll(() async {
      final loader = FontLoader(_family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      // Negative control: the line font, same code points.
      final line = FontLoader('control/PhosphorRegular')
        ..addFont(Future.value(ByteData.sublistView(
            File('fonts/Phosphor-Regular.ttf').readAsBytesSync())));
      await line.load();
    });

    testWidgets('control: the line font draws one flat colour', (tester) async {
      // Proves the checks below can fail: a monochrome glyph tinted red has
      // opaque pixels but no shading.
      final (opaque, _, colours) = _stats(await _render(
          tester, PhosphorIconsRegular.car,
          color: const Color(0xFFFF0000), family: 'control/PhosphorRegular'));
      expect(opaque, greaterThan(100));
      expect(colours, lessThan(4));
    });

    testWidgets('a glyph renders as a colour picture, not a tinted mask',
        (tester) async {
      final (opaque, saturated, colours) =
          _stats(await _render(tester, PhosphorIconsRegular.car));
      expect(opaque, greaterThan(500));
      expect(saturated, greaterThan(opaque ~/ 10));
      expect(colours, greaterThan(8));
    });

    testWidgets('the real call site, Icon(PhosphorIconsRegular.car), is 3D',
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: const Icon(PhosphorIconsRegular.car,
                size: 48, color: Color(0xFF000000)),
          ),
        ),
      ));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rgba = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      }))!;
      final (_, saturated, colours) = _stats(rgba);
      if (AppClay3D.on) {
        expect(saturated, greaterThan(100));
        expect(colours, greaterThan(8));
      } else {
        // Other builds: the line font (not loaded here), never colour.
        expect(saturated, 0);
      }
    });

    testWidgets('Icon.color does not recolour it', (tester) async {
      final black = _stats(await _render(tester, PhosphorIconsRegular.house));
      final red = _stats(await _render(tester, PhosphorIconsRegular.house,
          color: const Color(0xFFFF0000)));
      expect(black.$2, greaterThan(0), reason: 'saturated pixels in black');
      expect(red, black);
    });

    testWidgets('every icon the apps render has a colour glyph',
        (tester) async {
      final seen = <int>{};
      final blank = <String>[];
      for (final i in inventory) {
        if (!seen.add(i.icon.codePoint)) continue;
        final (opaque, _, colours) =
            _stats(await _render(tester, i.icon, size: 24));
        // Neutral-role renders are grey (no saturation), so the test is
        // shading: a real render has several tones, a flat mask one or two.
        if (opaque < 40 || colours < 4) {
          blank.add('${i.name} (opaque $opaque, colours $colours)');
        }
      }
      expect(seen.length, greaterThan(50));
      expect(blank, isEmpty);
    });
  });
}
