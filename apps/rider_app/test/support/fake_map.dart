import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Shared by the screenshot tests (Plan F screens, the proportion study).

Future<ui.Image> decodeTestImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

final String _flutterRoot =
    Platform.environment['FLUTTER_ROOT'] ??
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;

Future<void> loadTestFonts() async {
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
class FakeMapPainter extends CustomPainter {
  FakeMapPainter({
    required this.dark,
    required this.route,
    this.car,
    this.plate,
    this.routeTop = 0.14,
    this.routeBottom = 0.62,
  });

  /// Where the route's drop (top) and pickup (bottom) sit, as shares of the
  /// height — the stand-in for the real map's camera fit above the sheet.
  final double routeTop;
  final double routeBottom;

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
    double fy(double f) =>
        routeTop + (f - 0.14) / (0.62 - 0.14) * (routeBottom - routeTop);
    // Teal route with a soft glow (Plan F: "teal route with a glow").
    final teal = AppColors.highlightFor(dark);
    final pickup = Offset(size.width * 0.24, size.height * fy(0.62));
    final drop = Offset(size.width * 0.74, size.height * fy(0.14));
    final path = Path()
      ..moveTo(pickup.dx, pickup.dy)
      ..lineTo(size.width * 0.24, size.height * fy(0.46))
      ..lineTo(size.width * 0.55, size.height * fy(0.40))
      ..lineTo(size.width * 0.60, size.height * fy(0.24))
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
      final at = Offset(size.width * 0.24, size.height * fy(0.50));
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
  bool shouldRepaint(FakeMapPainter old) =>
      old.routeTop != routeTop || old.routeBottom != routeBottom;
}
