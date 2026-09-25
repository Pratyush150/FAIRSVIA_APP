import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A still "map snapshot" of a finished trip for the top of a trip detail
/// page: a quiet schematic street pattern (NOT real map tiles — no static-map
/// API is wired, and a live GoogleMap per history row would be a platform
/// view per page) with the trip's actual route drawn to scale over it —
/// the decoded polyline when the backend kept one, else a gentle arc from
/// pickup to drop-off — and the pickup ring / drop-off square at its ends.
///
/// [overlay] sits on top (e.g. glass pills with the distance and time).
class RouteSnapshot extends StatelessWidget {
  const RouteSnapshot({
    super.key,
    required this.path,
    this.height = 184,
    this.overlay,
    this.semanticLabel,
  });

  /// The route, pickup first. Two points draw an arc between them; fewer
  /// draw the streets alone.
  final List<LatLng> path;
  final double height;
  final Widget? overlay;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(AppSpacing.radiusXl);
    return Semantics(
      image: true,
      label: semanticLabel ?? 'Route map',
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child: CustomPaint(
                  painter: RouteSnapshotPainter(
                    path: path,
                    dark: dark,
                    route: AppColors.inkFor(dark),
                    ink: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              ?overlay,
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints [RouteSnapshot]. Public for golden/unit tests.
class RouteSnapshotPainter extends CustomPainter {
  RouteSnapshotPainter({
    required this.path,
    required this.dark,
    required this.route,
    required this.ink,
  });

  final List<LatLng> path;
  final bool dark;
  final Color route;
  final Color ink;

  /// Screen points for [path], fitted (aspect kept) inside [size] minus
  /// [pad]; a straight two-point path becomes a gentle arc.
  static List<Offset> project(List<LatLng> path, Size size, EdgeInsets pad) {
    final lat0 = path.first.latitude * math.pi / 180;
    final kx = math.cos(lat0);
    final raw = [
      for (final p in path) Offset(p.longitude * kx, -p.latitude),
    ];
    var minX = raw.first.dx, maxX = minX, minY = raw.first.dy, maxY = minY;
    for (final o in raw) {
      minX = math.min(minX, o.dx);
      maxX = math.max(maxX, o.dx);
      minY = math.min(minY, o.dy);
      maxY = math.max(maxY, o.dy);
    }
    final w = size.width - pad.horizontal, h = size.height - pad.vertical;
    final spanX = math.max(maxX - minX, 1e-9);
    final spanY = math.max(maxY - minY, 1e-9);
    final scale = math.min(w / spanX, h / spanY);
    final ox = pad.left + (w - spanX * scale) / 2;
    final oy = pad.top + (h - spanY * scale) / 2;
    final pts = [
      for (final o in raw)
        Offset(ox + (o.dx - minX) * scale, oy + (o.dy - minY) * scale),
    ];
    if (pts.length > 2) return pts;
    // Two points: an arc bowed to one side by a fifth of its length.
    final a = pts.first, b = pts.last;
    final mid = (a + b) / 2;
    final d = b - a;
    final normal = Offset(-d.dy, d.dx) * 0.2;
    final c = mid + normal;
    return [
      for (var i = 0; i <= 24; i++)
        () {
          final t = i / 24;
          final u = 1 - t;
          return a * (u * u) + c * (2 * u * t) + b * (t * t);
        }(),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final base = dark ? const Color(0xFF1A2025) : const Color(0xFFE9EDF0);
    final block = dark ? const Color(0xFF20272D) : const Color(0xFFF3F5F7);
    final street = dark ? const Color(0xFF2A3239) : const Color(0xFFFFFFFF);
    final park = dark ? const Color(0xFF1E2B25) : const Color(0xFFDCEBDF);
    final water = dark ? const Color(0xFF1A2733) : const Color(0xFFD5E4EE);

    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    // City blocks on a slightly rotated grid, so it reads as streets rather
    // than graph paper. Deterministic: every trip shares the same pattern.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.12);
    canvas.translate(-size.width / 2, -size.height / 2);
    const cell = 46.0, gap = 7.0;
    final blockPaint = Paint()..color = block;
    for (var x = -cell * 2; x < size.width + cell * 2; x += cell) {
      for (var y = -cell * 2; y < size.height + cell * 2; y += cell * 0.8) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x + gap / 2, y + gap / 2, cell - gap,
                cell * 0.8 - gap),
            const Radius.circular(3),
          ),
          blockPaint,
        );
      }
    }
    canvas.restore();

    // A park and a river so the snapshot is not a uniform grid.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.06, size.height * 0.58, size.width * 0.18,
            size.height * 0.3),
        const Radius.circular(10),
      ),
      Paint()..color = park,
    );
    final river = Path()
      ..moveTo(size.width * 0.62, -10)
      ..cubicTo(size.width * 0.72, size.height * 0.3, size.width * 0.9,
          size.height * 0.45, size.width + 10, size.height * 0.4);
    canvas.drawPath(
      river,
      Paint()
        ..color = water
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round,
    );

    // Two arterials.
    final arterial = Paint()
      ..color = street
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-10, size.height * 0.34),
        Offset(size.width + 10, size.height * 0.52), arterial);
    canvas.drawLine(Offset(size.width * 0.36, size.height + 10),
        Offset(size.width * 0.5, -10), arterial);

    // The route: a soft halo, then the line, then the two ends.
    if (path.length < 2) return;
    final pts = project(
      path,
      size,
      const EdgeInsets.fromLTRB(40, 32, 40, 72),
    );
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = route.withValues(alpha: dark ? 0.28 : 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = route
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final surface = dark ? const Color(0xFF12161A) : Colors.white;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: dark ? 0.5 : 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    // Pickup: a ring.
    final a = pts.first;
    canvas.drawCircle(a + const Offset(0, 1), 9, shadow);
    canvas.drawCircle(a, 9, Paint()..color = surface);
    canvas.drawCircle(
      a,
      5.5,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // Drop-off: a square.
    final b = pts.last;
    final outer = RRect.fromRectAndRadius(
        Rect.fromCenter(center: b, width: 18, height: 18),
        const Radius.circular(4));
    canvas.drawRRect(outer.shift(const Offset(0, 1)), shadow);
    canvas.drawRRect(outer, Paint()..color = ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: b, width: 6, height: 6),
          const Radius.circular(1)),
      Paint()..color = surface,
    );
  }

  @override
  bool shouldRepaint(RouteSnapshotPainter old) =>
      old.path != path ||
      old.dark != dark ||
      old.route != route ||
      old.ink != ink;
}
