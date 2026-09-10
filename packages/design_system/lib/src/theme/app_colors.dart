import 'package:flutter/material.dart';

/// Ride App palette. Warm, premium neutrals (stone-tinted, not cold grey) with a
/// single confident emerald brand — restraint over decoration. Legacy token
/// names are preserved so existing screens keep compiling while values sharpen.
class AppColors {
  AppColors._();

  // --- Brand (emerald) -------------------------------------------------------
  /// Primary brand colour — the emerald identity. Use for large fills, the
  /// switch track, dark-mode accent, decorative brand moments. NOTE: white text
  /// on this only reaches 2.62:1 (fails WCAG AA) — for text-bearing surfaces
  /// (filled CTA with a white label, emerald text/icon on light) use
  /// [accentInk] instead.
  static const Color accent = Color(0xFF12B76A);
  static const Color accentPressed = Color(0xFF0E9E5B);

  /// Accessible emerald for text-bearing surfaces: white label on this = 5.20:1
  /// (passes AA), and it's legible as emerald text/icons on light backgrounds.
  static const Color accentInk = Color(0xFF0A7D48);
  static const Color accentInkPressed = Color(0xFF086A3D);

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
  // Darkened from #8A837D (3.4:1, failed AA) to ~4.6:1 on light surfaces.
  static const Color textTertiaryLight = Color(0xFF6F6862);
  static const Color textPrimaryDark = Color(0xFFFAF9F7);
  static const Color textSecondaryDark = Color(0xFFA8A29E);
  // Lightened from #78716C (3.9:1, failed AA) to ~4.7:1 on dark surfaces.
  static const Color textTertiaryDark = Color(0xFF8A837D);

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
