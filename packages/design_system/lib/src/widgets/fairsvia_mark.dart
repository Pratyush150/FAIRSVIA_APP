import 'package:flutter/material.dart';

import '../theme/app_brand.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// The FAIRSVIA logomark ("Road-F"): an F whose stem is a road running away
/// from you, with a lane line — F for FAIRSVIA, a road for the ride. The same drawing
/// as the app icon and `docs/brand/`, painted here so it stays sharp at any
/// size with no image assets.
///
/// [driver] swaps to the driver app's colourway (navy tile, bright-blue F) so
/// the two apps never look alike.
class FairsviaMark extends StatelessWidget {
  const FairsviaMark({super.key, this.size = 64, this.driver = false});

  final double size;
  final bool driver;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: driver ? AppBrand.driverTitle : AppBrand.name,
      image: true,
      child: CustomPaint(size: Size.square(size), painter: _MarkPainter(driver)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.driver);

  final bool driver;

  static const _navy = Color(0xFF0B1F49);
  static const _teal = Color(0xFF2F6BFF);
  static const _turq = Color(0xFF5B9DFF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 512, size.height / 512);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 512, 512), const Radius.circular(116)),
      Paint()..color = driver ? _navy : _teal,
    );
    final v = Path()
      ..moveTo(134, 110)
      ..lineTo(378, 110)
      ..lineTo(378, 188)
      ..lineTo(226, 188)
      ..lineTo(226, 236)
      ..lineTo(332, 236)
      ..lineTo(332, 306)
      ..lineTo(226, 306)
      ..lineTo(226, 410)
      ..lineTo(134, 410)
      ..close();
    canvas.drawPath(v, Paint()..color = driver ? _turq : _navy);
    final lane = Paint()
      ..color = driver ? Colors.white : _turq
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(180, 332), const Offset(180, 358), lane);
    canvas.drawLine(const Offset(180, 378), const Offset(180, 396), lane);
    canvas.drawPath(
      Path()
        ..moveTo(208, 306)
        ..lineTo(226, 306)
        ..lineTo(226, 410)
        ..lineTo(208, 410)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.driver != driver;
}

/// The "Driver" pill set beside the FAIRSVIA mark or wordmark in the driver
/// app (splash lockup, login header), so a driver never mistakes it for the
/// rider app — the audit's brand lockup item 3.4.
///
/// Brand ink on its soft tint, in the current theme's brightness: readable in
/// light and dark and in every `THEME=` variant (the ink/soft pair is the one
/// used for selected rows).
class FairsviaDriverPill extends StatelessWidget {
  const FairsviaDriverPill({super.key, this.label = 'Driver'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.softFor(dark),
        borderRadius: BorderRadius.circular(AppSpacing.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: AppColors.accentTextFor(dark),
        ),
      ),
    );
  }
}
