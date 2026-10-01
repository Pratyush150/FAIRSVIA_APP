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

  /// Standard left/right margin of a screen or sheet's content (audit 3.3).
  static const double screenMargin = lg;

  // Control heights (audit 3.3: buttons 56 / 56 / 44). Primary and secondary
  // actions are 56 high; tertiary/text buttons at least 44, the touch-target
  // floor.
  static const double buttonHeight = 56;
  static const double buttonHeightTertiary = 44;

  // Corner radii. Generous, consistent rounding reads as premium. The v2
  // theme builds (THEME=midnight|daylight|daynight) use the audit's softer
  // 12 px controls and 20 px sheets.
  //
  // FAIRSVIA's shipped look (glass) is rounder still — 10/16/22/28 corners and
  // pill-shaped buttons — part of what sets it apart from RideVela, which
  // shares this codebase.
  static const bool _v2 = AppColors.v2;
  static const bool _fairsvia = AppColors.glass;
  static const double radiusSm = _fairsvia ? 10 : (_v2 ? 8 : 6);
  static const double radius = _fairsvia ? 16 : (_v2 ? 12 : 8);
  static const double radiusLg = _fairsvia ? 22 : (_v2 ? 16 : 12);
  static const double radiusXl = _fairsvia ? 28 : (_v2 ? 20 : 16);
  static const double pill = 999;

  /// Primary/secondary button corners: a full pill in FAIRSVIA's look,
  /// [radius] elsewhere.
  static const double buttonRadius = _fairsvia ? pill : radius;
}
