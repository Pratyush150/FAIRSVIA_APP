// FAIRSVIA's own glyphs added to the vendored Phosphor fonts
// (tool/ridevela_glyphs/build.py). Checks that each code point is really in
// both font files with an outline, and that it paints with roughly the same
// ink as the Phosphor icon it sits beside (so it isn't a hairline or a blob).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Glyph outline size in bytes for [codePoint] in a TrueType file, or 0 when
/// the code point is unmapped or maps to an empty glyph. Reads the Windows
/// Unicode BMP cmap (format 4), then loca.
int glyphOutlineBytes(Uint8List ttf, int codePoint) {
  final d = ByteData.sublistView(ttf);
  final tables = <String, int>{};
  for (var i = 0; i < d.getUint16(4); i++) {
    final rec = 12 + i * 16;
    tables[String.fromCharCodes(ttf.sublist(rec, rec + 4))] =
        d.getUint32(rec + 8);
  }
  final cmap = tables['cmap']!;
  int? sub;
  for (var i = 0; i < d.getUint16(cmap + 2); i++) {
    final rec = cmap + 4 + i * 8;
    if (d.getUint16(rec) == 3 && d.getUint16(rec + 2) == 1) {
      sub = cmap + d.getUint32(rec + 4);
    }
  }
  if (sub == null || d.getUint16(sub) != 4) return 0;
  final segs = d.getUint16(sub + 6) ~/ 2;
  final ends = sub + 14, starts = ends + segs * 2 + 2;
  final deltas = starts + segs * 2, offsets = deltas + segs * 2;
  var glyph = 0;
  for (var s = 0; s < segs; s++) {
    if (codePoint > d.getUint16(ends + s * 2)) continue;
    if (codePoint < d.getUint16(starts + s * 2)) break;
    final ro = d.getUint16(offsets + s * 2);
    if (ro == 0) {
      glyph = (codePoint + d.getInt16(deltas + s * 2)) & 0xffff;
    } else {
      final at = offsets + s * 2 + ro + (codePoint - d.getUint16(starts + s * 2)) * 2;
      final g = d.getUint16(at);
      glyph = g == 0 ? 0 : (g + d.getInt16(deltas + s * 2)) & 0xffff;
    }
    break;
  }
  if (glyph == 0) return 0;
  final longLoca = d.getInt16(tables['head']! + 50) == 1;
  final loca = tables['loca']!;
  int off(int g) =>
      longLoca ? d.getUint32(loca + g * 4) : d.getUint16(loca + g * 2) * 2;
  return off(glyph + 1) - off(glyph);
}

Future<void> _loadPhosphor() async {
  for (final (family, file) in [
    ('packages/design_system/PhosphorRegular', 'Phosphor-Regular.ttf'),
    ('packages/design_system/PhosphorFill', 'Phosphor-Fill.ttf'),
  ]) {
    final loader = FontLoader(family)
      ..addFont(File('fonts/$file').readAsBytes().then((b) => b.buffer.asByteData()));
    await loader.load();
  }
}

/// Sum of darkness (0..1 per pixel) of [icon] painted black on white at 48 px.
Future<double> _ink(WidgetTester tester, IconData icon) async {
  final key = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: const Color(0xFFFFFFFF),
          child: Icon(icon, size: 48, color: const Color(0xFF000000)),
        ),
      ),
    ),
  ));
  late double ink;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final px = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    ink = 0;
    for (var i = 0; i < px.lengthInBytes; i += 4) {
      ink += 1 - px.getUint8(i) / 255;
    }
  });
  return ink;
}

void main() {
  const additions = {
    'autoRickshaw': (PhosphorIconsRegular.autoRickshaw, PhosphorIconsFill.autoRickshaw),
    'cashRupee': (PhosphorIconsRegular.cashRupee, PhosphorIconsFill.cashRupee),
  };

  group('font files', () {
    for (final (weight, file) in [('Regular', 'Phosphor-Regular.ttf'), ('Fill', 'Phosphor-Fill.ttf')]) {
      final ttf = File('fonts/$file').readAsBytesSync();
      test('$weight: every addition has an outline at its code point', () {
        expect(glyphOutlineBytes(ttf, PhosphorIconsRegular.car.codePoint), greaterThan(0),
            reason: 'parser sanity: Phosphor car');
        expect(glyphOutlineBytes(ttf, 0xf8f9), 0, reason: 'parser sanity: unmapped');
        for (final MapEntry(key: name, value: (regular, fill)) in additions.entries) {
          expect(regular.codePoint, fill.codePoint);
          expect(glyphOutlineBytes(ttf, regular.codePoint), greaterThan(0), reason: name);
        }
      });
    }
  });

  group('painted weight', () {
    // Ink relative to the Phosphor icon each one sits next to in the app.
    final pairs = {
      'autoRickshaw vs car': (
        PhosphorIconsRegular.autoRickshaw, PhosphorIconsRegular.car,
        PhosphorIconsFill.autoRickshaw, const IconData(0xe112, fontFamily: 'PhosphorFill', fontPackage: 'design_system'),
      ),
      'cashRupee vs money': (
        PhosphorIconsRegular.cashRupee, PhosphorIconsRegular.money,
        PhosphorIconsFill.cashRupee, const IconData(0xe588, fontFamily: 'PhosphorFill', fontPackage: 'design_system'),
      ),
    };
    for (final MapEntry(key: name, value: (ours, theirs, oursFill, theirsFill)) in pairs.entries) {
      testWidgets(name, (tester) async {
        await tester.runAsync(_loadPhosphor);
        for (final (a, b) in [(ours, theirs), (oursFill, theirsFill)]) {
          final inkA = await _ink(tester, a), inkB = await _ink(tester, b);
          // The test font (Ahem) paints a solid em square; a real line icon
          // covers well under half of it. Guards against the font not loading.
          expect(inkA, inExclusiveRange(0, 0.6 * 48 * 48), reason: '${a.fontFamily} ink $inkA');
          final ratio = inkA / inkB;
          expect(ratio, inInclusiveRange(0.7, 1.4), reason: '${a.fontFamily} ink ratio $ratio');
        }
      });
    }
  });
}
