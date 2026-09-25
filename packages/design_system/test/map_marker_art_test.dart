import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

// Direct import: keeps this test independent of the rest of the barrel.
import 'package:design_system/src/widgets/map_marker_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  return (await codec.getNextFrame()).image;
}

Future<Color> _pixel(ui.Image img, Offset logical, double ratio) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final x = (logical.dx * ratio).round(), y = (logical.dy * ratio).round();
  final i = (y * img.width + x) * 4;
  return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i),
      data.getUint8(i + 1), data.getUint8(i + 2));
}

void main() {
  test('pin anchor is the tip, near the bottom-centre of the canvas', () {
    expect(MapMarkerArt.pinAnchor.dx, 0.5);
    expect(MapMarkerArt.pinAnchor.dy, closeTo(41 / 46, 1e-9));
    // The tip is the lowest point of the outline, centred horizontally.
    final path = MapMarkerArt.pinPath();
    const tipY = 41.0;
    expect(path.contains(const Offset(17, tipY - 1)), isTrue);
    expect(path.contains(const Offset(17, tipY + 0.5)), isFalse);
    expect(path.contains(const Offset(15, tipY - 1)), isFalse);
    // Round head, symmetric about x = 17.
    for (final dx in [-12.5, 12.5]) {
      expect(path.contains(Offset(17 + dx, 16)), isTrue);
      expect(path.contains(Offset(17 + dx * 1.1, 16)), isFalse);
    }
  });

  testWidgets('renders solid pins and the me-dot at the declared sizes',
      (tester) async {
    await tester.runAsync(() async {
      const r = 3.0;
      final pickup = await _decode(
          await MapMarkerArt.render(MapMarkerArtKind.pickup, pixelRatio: r));
      final drop = await _decode(
          await MapMarkerArt.render(MapMarkerArtKind.dropoff, pixelRatio: r));
      final me = await _decode(
          await MapMarkerArt.render(MapMarkerArtKind.me, pixelRatio: r));
      expect(pickup.width, (34 * r).ceil());
      expect(pickup.height, (46 * r).ceil());
      expect(me.width, (36 * r).ceil());

      // Solid body: the head (between the white centre and the rim) is the
      // opaque fill, not transparent like the old ring.
      final body = await _pixel(pickup, const Offset(17, 8), r);
      expect(body.a, 1.0);
      expect(body.b, greaterThan(body.r)); // teal ink, not white/black
      // White centre dot / square.
      expect(await _pixel(pickup, const Offset(17, 16), r),
          const Color(0xFFFFFFFF));
      expect(await _pixel(drop, const Offset(17, 16), r),
          const Color(0xFFFFFFFF));
      final dropBody = await _pixel(drop, const Offset(17, 27), r);
      expect(dropBody.a, 1.0);
      expect(dropBody.r, lessThan(0.3)); // dark
      // Me-dot: white ring, blue core, translucent halo.
      expect(await _pixel(me, const Offset(18, 10.2), r),
          const Color(0xFFFFFFFF));
      final core = await _pixel(me, const Offset(18, 19), r);
      expect(core.b, greaterThan(0.8));
      final halo = await _pixel(me, const Offset(18, 4), r);
      expect(halo.a, inExclusiveRange(0.05, 0.5));

      // Contact sheet for review, on a light and a dark basemap tone.
      final out = Platform.environment['MARKER_PNG'];
      if (out != null) {
        const w = 360.0, h = 150.0;
        final rec = ui.PictureRecorder();
        final c = Canvas(rec)..scale(r);
        c.drawRect(const Rect.fromLTWH(0, 0, w / 2, h),
            Paint()..color = const Color(0xFFEDEFF1));
        c.drawRect(const Rect.fromLTWH(w / 2, 0, w / 2, h),
            Paint()..color = const Color(0xFF1D2229));
        void put(ui.Image img, double x, double y, Size s) => c.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(x, y, s.width * 1.6, s.height * 1.6),
            Paint()..filterQuality = FilterQuality.high);
        for (final ox in [0.0, w / 2]) {
          put(pickup, ox + 12, 40, MapMarkerArt.pinSize);
          put(drop, ox + 68, 40, MapMarkerArt.pinSize);
          put(me, ox + 124, 50, MapMarkerArt.meSize);
        }
        final img = await rec
            .endRecording()
            .toImage((w * r).round(), (h * r).round());
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File(out).writeAsBytesSync(png!.buffer.asUint8List());
      }
    });
  });

  testWidgets('MapPinMark paints at its scaled size', (tester) async {
    await tester.pumpWidget(const Center(
        child: MapPinMark(fill: Color(0xFF007A7A), scale: 1.2)));
    final size = tester.getSize(find.byType(MapPinMark));
    expect(size.width, closeTo(34 * 1.2, 0.01));
    expect(size.height, closeTo(46 * 1.2, 0.01));
  });
}
