import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Which map marker [MapMarkerArt.render] draws.
enum MapMarkerArtKind { pickup, dropoff, me }

/// The drawn map markers, shared by [AppMap]'s bitmap markers and the map
/// picker's fixed centre pin so every map in both apps shows the same art.
///
/// * Pickup: a solid brand-ink teardrop pin, white rim, white centre dot.
/// * Drop-off: a solid near-black teardrop pin, white rim, white centre square
///   (the square keeps "destination" readable at a glance).
/// * Me: the "you are here" dot — blue core with a soft gradient, white ring,
///   and a translucent halo with a crisp outer ring.
///
/// Every mark has a white rim and a soft drop shadow, so it holds on the light
/// and the dark basemap alike.
abstract final class MapMarkerArt {
  /// Logical canvas of a pin, shadow included.
  static const Size pinSize = Size(34, 46);

  /// Where the pin's tip lands, as a fraction of [pinSize] — the marker anchor.
  static const Offset pinAnchor = Offset(0.5, _tipY / 46);

  /// Logical canvas of the "me" dot (centred anchor).
  static const Size meSize = Size(36, 36);

  static const double _tipY = 41;
  static const Offset _head = Offset(17, 16);
  static const double _headR = 13;

  /// Pickup fill: the light-mode brand ink (deep teal), the strongest against
  /// the white rim on either basemap.
  static Color get pickupFill => AppColors.inkFor(false);

  /// Drop-off fill.
  static const Color dropoffFill = Color(0xFF0F1417);

  static const Color meBlue = Color(0xFF1A73E8);

  /// Teardrop outline in [pinSize] coordinates: a circle head with straight
  /// tangents down to the tip.
  static Path pinPath() {
    const d = _tipY - 16; // head centre → tip
    final phi = math.acos(_headR / d);
    return Path()
      ..moveTo(_head.dx, _tipY)
      ..arcTo(Rect.fromCircle(center: _head, radius: _headR),
          math.pi / 2 + phi, 2 * math.pi - 2 * phi, false)
      ..close();
  }

  /// Paints a pin in [pinSize] coordinates. [square] draws the drop-off's
  /// white square centre instead of the pickup's dot.
  static void paintPin(Canvas canvas, {required Color fill, bool square = false}) {
    final path = pinPath();
    // Ground contact shadow under the tip, then a soft body shadow.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(17, _tipY + 1), width: 12, height: 4),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawPath(
      path.shift(const Offset(0, 1.5)),
      Paint()
        ..color = const Color(0x4D000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    // Solid body with a gentle top-lit gradient.
    final light = Color.lerp(fill, Colors.white, 0.22)!;
    final deep = Color.lerp(fill, Colors.black, 0.12)!;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
            const Offset(17, 3), const Offset(17, _tipY), [light, deep]),
    );
    // White rim so the pin reads on any map colour.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
    final white = Paint()..color = Colors.white;
    if (square) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: _head, width: 10, height: 10),
            const Radius.circular(2)),
        white,
      );
    } else {
      canvas.drawCircle(_head, 5, white);
    }
  }

  /// Paints the "you are here" dot in [meSize] coordinates.
  static void paintMe(Canvas canvas) {
    const c = Offset(18, 18);
    canvas.drawCircle(c, 17, Paint()..color = meBlue.withValues(alpha: 0.14));
    canvas.drawCircle(
      c,
      16.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = meBlue.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      c + const Offset(0, 1),
      9.5,
      Paint()
        ..color = const Color(0x4D000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(c, 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      6.5,
      Paint()
        ..shader = ui.Gradient.radial(c + const Offset(-2, -2), 8,
            [const Color(0xFF5E9BFF), meBlue]),
    );
  }

  /// Logical size of [kind]'s canvas.
  static Size sizeOf(MapMarkerArtKind kind) =>
      kind == MapMarkerArtKind.me ? meSize : pinSize;

  /// Rasterises [kind] to PNG bytes at [pixelRatio]; draw the result at
  /// [sizeOf] logical size.
  static Future<Uint8List> render(MapMarkerArtKind kind,
      {double pixelRatio = 3}) async {
    final size = sizeOf(kind);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    switch (kind) {
      case MapMarkerArtKind.pickup:
        paintPin(canvas, fill: pickupFill);
      case MapMarkerArtKind.dropoff:
        paintPin(canvas, fill: dropoffFill, square: true);
      case MapMarkerArtKind.me:
        paintMe(canvas);
    }
    final img = await recorder.endRecording().toImage(
        (size.width * pixelRatio).ceil(), (size.height * pixelRatio).ceil());
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      img.dispose();
    }
  }
}

/// A [MapMarkerArt] pin as a widget — the map picker's fixed centre pin.
/// Its tip sits at `MapMarkerArt.pinAnchor` of its box.
class MapPinMark extends StatelessWidget {
  const MapPinMark({super.key, required this.fill, this.scale = 1.15});

  final Color fill;
  final double scale;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: MapMarkerArt.pinSize * scale,
        painter: _PinPainter(fill, scale),
      );
}

class _PinPainter extends CustomPainter {
  _PinPainter(this.fill, this.scale);
  final Color fill;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    MapMarkerArt.paintPin(canvas, fill: fill);
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.fill != fill || old.scale != scale;
}
