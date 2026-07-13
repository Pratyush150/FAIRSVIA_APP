import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A neutral stand-in for the live map, shown on platforms/builds where Google
/// Maps isn't available yet (e.g. web without a Maps JS key). Keeps the rest of
/// the screen usable so flows can be tested without tiles.
class MapPlaceholder extends StatelessWidget {
  const MapPlaceholder({super.key, this.note});

  /// Optional caption; defaults to a hint about the missing Maps key.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppColors.surfaceDark : const Color(0xFFE8EBF0);
    final line = isDark ? AppColors.borderDark : const Color(0xFFD2D8E0);
    return DecoratedBox(
      decoration: BoxDecoration(color: base),
      child: CustomPaint(
        painter: _GridPainter(line),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined,
                  size: 48, color: AppColors.accent.withValues(alpha: 0.7)),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Text(
                  note ?? 'Map preview — add a Google Maps key to see live tiles',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A faint street-grid so the placeholder reads as "a map area".
class _GridPainter extends CustomPainter {
  _GridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 48.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.color != color;
}
