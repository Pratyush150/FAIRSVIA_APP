import 'package:flutter/material.dart';

/// UberNav palette. Warm, premium neutrals (stone-tinted, not cold grey) with a
/// single confident emerald brand — restraint over decoration. Legacy token
/// names are preserved so existing screens keep compiling while values sharpen.
class AppColors {
  AppColors._();

  // --- Brand (emerald) -------------------------------------------------------
  /// Primary brand + CTA colour.
  static const Color accent = Color(0xFF12B76A);
  static const Color accentPressed = Color(0xFF0E9E5B);
  /// Tinted brand wash for selected states, chips, highlights (light mode).
  static const Color accentSoft = Color(0xFFE7F6EF);
  static const Color accentSoftDark = Color(0xFF10241B);
  static const Color onAccent = Color(0xFFFFFFFF);

  /// Near-black brand ink (buttons on light surfaces, dark chrome).
  static const Color primary = Color(0xFF1C1917);
  static const Color primaryElevated = Color(0xFF2A2724);

  // --- Surfaces & canvas (warm) ----------------------------------------------
  static const Color surfaceLight = Color(0xFFFFFFFF);
  /// Muted fill for inset cards, inputs, chips on light.
  static const Color surfaceMutedLight = Color(0xFFF5F3F0);
  static const Color backgroundLight = Color(0xFFFAF9F7);

  static const Color surfaceDark = Color(0xFF1C1A19);
  static const Color surfaceMutedDark = Color(0xFF262220);
  static const Color backgroundDark = Color(0xFF121110);

  // --- Text ------------------------------------------------------------------
  static const Color textPrimaryLight = Color(0xFF1C1917);
  static const Color textSecondaryLight = Color(0xFF57534E);
  static const Color textTertiaryLight = Color(0xFF8A837D);
  static const Color textPrimaryDark = Color(0xFFFAF9F7);
  static const Color textSecondaryDark = Color(0xFFA8A29E);
  static const Color textTertiaryDark = Color(0xFF78716C);

  // --- Lines -----------------------------------------------------------------
  static const Color borderLight = Color(0xFFE7E3DE);
  static const Color borderDark = Color(0xFF34302C);

  // --- Semantic --------------------------------------------------------------
  static const Color success = Color(0xFF17B26A);
  static const Color warning = Color(0xFFF79009);
  static const Color error = Color(0xFFF04438);
  static const Color info = Color(0xFF2E90FA);
  /// Rating stars / premium accents.
  static const Color star = Color(0xFFFBBF24);

  /// Modal scrim behind sheets/dialogs.
  static const Color scrim = Color(0x66000000);
}
