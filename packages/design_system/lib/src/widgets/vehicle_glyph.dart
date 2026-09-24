import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A side-view car illustration per ride type — a compact hatchback, a
/// sedan, a tall MPV and a long black premium sedan — so the ride list reads
/// at a glance, the way ride-hailing apps show each class. Drawn here (our
/// own artwork), so it scales crisply and needs no image assets.
class VehicleGlyph extends StatelessWidget {
  const VehicleGlyph({super.key, required this.tier, this.width = 64});

  /// `economy`, `comfort`, `xl` or `premium` (anything else draws a sedan).
  final String tier;
  final double width;

  /// Which illustrated set the build uses, or null for the drawn glyphs:
  /// the flat silver 3/4-view cars (audit 2.7) for the shipped turquoise
  /// build and Plan A (midnight), Plan B's 3D cars (daylight), and for Plan C
  /// (daynight) whichever matches the current mode. The black-and-white
  /// `mono` build keeps the drawn glyphs (the art has a teal stripe).
  static String? artSet(bool dark) => switch (AppColors.variant) {
        'daylight' => 'daylight',
        'daynight' => dark ? 'midnight' : 'daylight',
        'mono' => null,
        _ => 'midnight',
      };

  static String _file(String tier) => switch (tier) {
        'economy' || 'comfort' || 'xl' || 'premium' => tier,
        _ => 'comfort',
      };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final painted = CustomPaint(
      size: Size(width, width * 0.5),
      painter: _VehiclePainter(_shapeFor(tier), dark),
    );
    final set = artSet(dark);
    return Semantics(
      label: '$tier car',
      child: set == null
          ? painted
          : Image.asset(
              'packages/design_system/assets/vehicles/$set/${_file(tier)}.png',
              width: width,
              height: width * 0.625,
              fit: BoxFit.contain,
              // A missing asset must never blank the ride list.
              errorBuilder: (_, _, _) => painted,
            ),
    );
  }

  static _Shape _shapeFor(String tier) => switch (tier) {
        'economy' => _Shape.hatchback,
        'xl' => _Shape.mpv,
        'premium' => _Shape.premium,
        _ => _Shape.sedan,
      };
}

enum _Shape { hatchback, sedan, mpv, premium }

class _VehiclePainter extends CustomPainter {
  _VehiclePainter(this.shape, this.dark);

  final _Shape shape;
  final bool dark;

  // Body colours per class: turquoise, teal-navy, slate, black.
  Color get _body => switch (shape) {
        _Shape.hatchback => const Color(0xFF0FA3A8),
        _Shape.sedan => const Color(0xFF0B3C49),
        _Shape.mpv => const Color(0xFF5B6770),
        _Shape.premium => const Color(0xFF15181B),
      };

  @override
  void paint(Canvas canvas, Size size) {
    // Draw in a 100 × 50 box, scaled to the widget.
    canvas.scale(size.width / 100, size.height / 50);

    // Shadow under the car.
    canvas.drawOval(
      const Rect.fromLTWH(8, 43, 84, 5),
      Paint()..color = Colors.black.withValues(alpha: dark ? 0.35 : 0.12),
    );

    final body = Path();
    final glass = Path();
    late double frontWheel, rearWheel;
    switch (shape) {
      case _Shape.hatchback:
        // Short nose, tall roof falling straight at the back.
        body
          ..moveTo(10, 40)
          ..lineTo(10, 29)
          ..quadraticBezierTo(11, 25, 16, 24)
          ..lineTo(28, 22)
          ..lineTo(40, 11)
          ..quadraticBezierTo(43, 9, 48, 9)
          ..lineTo(72, 9)
          ..quadraticBezierTo(78, 9, 81, 14)
          ..lineTo(86, 24)
          ..quadraticBezierTo(90, 26, 90, 31)
          ..lineTo(90, 40)
          ..close();
        glass
          ..moveTo(33, 22)
          ..lineTo(43, 13)
          ..lineTo(58, 13)
          ..lineTo(58, 22)
          ..close()
          ..moveTo(61, 13)
          ..lineTo(74, 13)
          ..quadraticBezierTo(77, 13, 79, 17)
          ..lineTo(81, 22)
          ..lineTo(61, 22)
          ..close();
        frontWheel = 24;
        rearWheel = 76;
      case _Shape.sedan:
      case _Shape.premium:
        final long = shape == _Shape.premium;
        // Bonnet, cabin, then a boot — a three-box saloon.
        body
          ..moveTo(4, 40)
          ..lineTo(4, 30)
          ..quadraticBezierTo(5, 26, 10, 25)
          ..lineTo(long ? 30 : 28, 23)
          ..lineTo(long ? 41 : 39, 13)
          ..quadraticBezierTo(44, 11, 49, 11)
          ..lineTo(long ? 68 : 66, 11)
          ..quadraticBezierTo(72, 11, 75, 15)
          ..lineTo(80, 22)
          ..lineTo(92, 24)
          ..quadraticBezierTo(96, 25, 96, 30)
          ..lineTo(96, 40)
          ..close();
        glass
          ..moveTo(long ? 34 : 32, 22)
          ..lineTo(long ? 43 : 42, 14.5)
          ..lineTo(57, 14.5)
          ..lineTo(57, 22)
          ..close()
          ..moveTo(60, 14.5)
          ..lineTo(long ? 68 : 66, 14.5)
          ..quadraticBezierTo(70, 14.5, 72, 17)
          ..lineTo(75, 22)
          ..lineTo(60, 22)
          ..close();
        frontWheel = 22;
        rearWheel = 78;
      case _Shape.mpv:
        // Tall and boxy with three windows: room for six.
        body
          ..moveTo(5, 40)
          ..lineTo(5, 28)
          ..quadraticBezierTo(6, 23, 12, 22)
          ..lineTo(22, 20)
          ..lineTo(30, 7)
          ..quadraticBezierTo(32, 5, 36, 5)
          ..lineTo(88, 5)
          ..quadraticBezierTo(94, 5, 95, 11)
          ..lineTo(95, 40)
          ..close();
        glass
          ..moveTo(26, 20)
          ..lineTo(33, 9)
          ..lineTo(48, 9)
          ..lineTo(48, 20)
          ..close()
          ..moveTo(51, 9)
          ..lineTo(68, 9)
          ..lineTo(68, 20)
          ..lineTo(51, 20)
          ..close()
          ..moveTo(71, 9)
          ..lineTo(89, 9)
          ..quadraticBezierTo(91, 9, 91, 12)
          ..lineTo(91, 20)
          ..lineTo(71, 20)
          ..close();
        frontWheel = 22;
        rearWheel = 78;
    }

    final bounds = body.getBounds();
    final top = bounds.top;
    final bottom = bounds.bottom;

    // Dark wheel arches first, so the body reads as sitting over the wheels.
    for (final x in [frontWheel, rearWheel]) {
      canvas.drawCircle(Offset(x, 40), 9.6, Paint()..color = const Color(0xFF0E1012));
    }

    // Painted body: lighter on the roof, deeper along the sills.
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(_body, Colors.white, 0.22)!,
            _body,
            Color.lerp(_body, Colors.black, 0.28)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromLTRB(0, top, 100, bottom)),
    );
    // Re-cut the arches over the body edge.
    for (final x in [frontWheel, rearWheel]) {
      canvas.drawArc(Rect.fromCircle(center: Offset(x, 40), radius: 9.6), 3.14159, 3.14159, true,
          Paint()..color = const Color(0xFF0E1012));
    }
    // A thin edge keeps the black premium car visible on a dark sheet.
    if (dark) {
      canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.white.withValues(alpha: 0.28),
      );
    }

    // Tinted glass with a sky reflection and a diagonal streak.
    final glassBounds = glass.getBounds();
    canvas.drawPath(
      glass,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE6F4F6), Color(0xFF9FC4CC), Color(0xFF5E7F88)],
        ).createShader(glassBounds),
    );
    canvas.save();
    canvas.clipPath(glass);
    canvas.drawPath(
      Path()
        ..moveTo(glassBounds.left + glassBounds.width * 0.30, glassBounds.top)
        ..lineTo(glassBounds.left + glassBounds.width * 0.42, glassBounds.top)
        ..lineTo(glassBounds.left + glassBounds.width * 0.28, glassBounds.bottom)
        ..lineTo(glassBounds.left + glassBounds.width * 0.16, glassBounds.bottom)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
    canvas.restore();

    // Shoulder highlight and a door seam below the window pillar.
    canvas.drawLine(Offset(bounds.left + 8, 26.5), Offset(bounds.right - 6, 26.5),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.22)
          ..strokeWidth = 0.9);
    final seamX = glassBounds.left + glassBounds.width * 0.52;
    canvas.drawLine(Offset(seamX, glassBounds.bottom + 1), Offset(seamX, 38),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28)
          ..strokeWidth = 0.7);
    // Door handle.
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(seamX + 3, 28, 5, 1.4), const Radius.circular(0.7)),
        Paint()..color = Colors.black.withValues(alpha: 0.3));
    // Side mirror at the base of the windscreen.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(glassBounds.left - 2.5, glassBounds.bottom - 3.5, 4, 2.8),
            const Radius.circular(1)),
        Paint()..color = Color.lerp(_body, Colors.black, 0.35)!);

    // Headlight on the bonnet (left), tail-light at the back (right).
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bounds.left - 0.5, 27, 5.5, 3.2), const Radius.circular(1.4)),
        Paint()..color = const Color(0xFFFFF1C2));
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bounds.right - 4.2, 27, 4.5, 3.6), const Radius.circular(1.2)),
        Paint()..color = const Color(0xFFE5484D));

    // Tyres with five-spoke alloys.
    for (final x in [frontWheel, rearWheel]) {
      final c = Offset(x, 40);
      canvas.drawCircle(c, 7.8, Paint()..color = const Color(0xFF1B1D1F));
      canvas.drawCircle(c, 4.9,
          Paint()
            ..shader = const RadialGradient(
              colors: [Color(0xFFE9EDF0), Color(0xFF9AA3AA)],
            ).createShader(Rect.fromCircle(center: c, radius: 4.9)));
      final spoke = Paint()
        ..color = const Color(0xFF6E777E)
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 5; i++) {
        final a = i * 2 * 3.14159 / 5 - 3.14159 / 2;
        canvas.drawLine(c, c + Offset(4.2 * _cos(a), 4.2 * _sin(a)), spoke);
      }
      canvas.drawCircle(c, 1.3, Paint()..color = const Color(0xFF3A4046));
    }
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(_VehiclePainter old) => old.shape != shape || old.dark != dark;
}
