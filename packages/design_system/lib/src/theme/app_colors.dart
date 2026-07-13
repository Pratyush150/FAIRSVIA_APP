import 'package:flutter/material.dart';

/// UberNav palette: near-black primary, a single electric-green accent,
/// semantic colors, and light/dark surfaces.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1A1A1A);
  static const Color primaryElevated = Color(0xFF2C2C2E);
  static const Color accent = Color(0xFF00C46A);
  static const Color accentPressed = Color(0xFF00A85B);

  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color backgroundLight = Color(0xFFF5F5F7);
  static const Color backgroundDark = Color(0xFF000000);

  static const Color success = Color(0xFF2FBF71);
  static const Color warning = Color(0xFFF5A623);
  static const Color error = Color(0xFFE5484D);

  static const Color textPrimaryLight = Color(0xFF1A1A1A);
  static const Color textSecondaryLight = Color(0xFF6B6B70);
  static const Color textPrimaryDark = Color(0xFFF5F5F5);
  static const Color textSecondaryDark = Color(0xFF9E9EA4);

  static const Color borderLight = Color(0xFFE2E2E6);
  static const Color borderDark = Color(0xFF3A3A3C);
}
