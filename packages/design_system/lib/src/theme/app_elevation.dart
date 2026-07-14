import 'package:flutter/material.dart';

/// Soft, layered shadows. Low-opacity and warm-neutral so cards and sheets lift
/// off the canvas without the heavy Material drop-shadow look.
class AppElevation {
  AppElevation._();

  /// Resting cards, chips.
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0F1C1917), blurRadius: 8, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x0A1C1917), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// Raised cards, floating buttons.
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x141C1917), blurRadius: 18, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0A1C1917), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// Bottom sheets and prominent floating panels.
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x1F1C1917), blurRadius: 32, offset: Offset(0, -6)),
    BoxShadow(color: Color(0x0F1C1917), blurRadius: 8, offset: Offset(0, -2)),
  ];

  /// Circular map/overlay buttons floating over the map.
  static const List<BoxShadow> float = [
    BoxShadow(color: Color(0x241C1917), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
