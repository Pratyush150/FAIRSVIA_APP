import 'app_colors.dart';

/// 4px base spacing grid + corner radii, shared across the apps.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double x20 = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
  static const double huge = 48;

  // Corner radii. Generous, consistent rounding reads as premium. The v2
  // theme builds (THEME=midnight|daylight|daynight) use the audit's softer
  // 12 px controls and 20 px sheets.
  static const bool _v2 = AppColors.v2;
  static const double radiusSm = _v2 ? 8 : 6;
  static const double radius = _v2 ? 12 : 8;
  static const double radiusLg = _v2 ? 16 : 12;
  static const double radiusXl = _v2 ? 20 : 16;
  static const double pill = 999;
}
