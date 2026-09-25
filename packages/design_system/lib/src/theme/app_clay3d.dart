import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// Plan G — "3D Clay" (`--dart-define=THEME=clay3d`).
///
/// Every icon in the app is a Blender-rendered 3D picture. That needs no
/// call-site change: under this build [PhosphorIconsRegular] and
/// [PhosphorIconsFill] name the 'Phosphor3D' font, a colour-bitmap font whose
/// glyph at each Phosphor code point is the 3D render of that icon
/// (CBDT/CBLC for Android, sbix for iOS; built by tool/icons3d/build.py from
/// docs/brand/icons3d/png/dark). Colour bitmaps ignore `Icon.color`, so the
/// icons keep their own lighting and colours on every surface.
///
/// Dark mode: ONE set serves both themes — the dark-mode renders (brighter
/// bodies, rim light, no floor shadow) read well on the light page as well,
/// so the bundled font never has to be swapped at run time (the engine could
/// only swap it one way per launch).
abstract final class AppClay3D {
  static const bool on = AppColors.clay3d;

  /// The 3D hero image for a hero name ('add_stop', 'prebook', 'done', 'cash'
  /// …), under `packages/design_system/`: the same render as the matching
  /// icon (see tool/icons3d/build.py HEROES), at 256 px.
  static String heroAsset(String name, bool dark) =>
      'assets/heroes/${dark ? 'clay3d_dark' : 'clay3d'}/$name.png';

  /// Regular and Fill are the same 3D picture in this build, so an icon
  /// whose *off* state was the Regular outline (an empty rating star, an
  /// un-favourited heart) would look on. Wrap such an icon in [off] when it
  /// shows the off state: under clay3d it is drawn greyscale at 45 %
  /// opacity (a colour bitmap ignores `Icon.color`, but not a colour
  /// filter); every other build gets [icon] back untouched.
  static Widget off(Widget icon) {
    if (!on) return icon;
    return Opacity(
      opacity: 0.45,
      child: ColorFiltered(colorFilter: _greyscale, child: icon),
    );
  }

  static const ColorFilter _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  /// Formerly swapped in a dark icon font; one set now serves both themes.
  static Future<void> useIconSetFor(Brightness brightness) =>
      // One 3D set now serves both themes (see tool/icons3d/build.py), so
      // there is nothing to swap. Kept so callers need no change.
      Future.value();
}

/// Icon sizes that grow under THEME=clay3d: a 3D render has its own shading
/// and ground shadow, so it needs a few more pixels than a line glyph to read.
/// Every other build keeps the audit's 24 / 20 / 16 steps.
abstract final class AppIconSize {
  /// List / menu row leading icon.
  static const double row = AppClay3D.on ? 28 : 24;

  /// Row chevrons and small trailing actions.
  static const double trailing = AppClay3D.on ? 22 : 20;

  /// Floating map buttons (menu, recenter).
  static const double mapButton = AppClay3D.on ? 26 : 24;

  /// Chip / pill glyphs.
  static const double chip = AppClay3D.on ? 22 : 20;

  /// Inline glyphs beside a label (chips, "Later", fare lines).
  static const double inline = AppClay3D.on ? 20 : 16;

  /// Unsized icons (the theme default).
  static const double utility = AppClay3D.on ? 26 : 24;
}
