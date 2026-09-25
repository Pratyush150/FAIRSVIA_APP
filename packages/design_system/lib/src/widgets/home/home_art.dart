import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Home-screen surface tokens shared by [ServiceTile], [ContextCard] and the
/// promo banners: a surface one step lighter than the page, with a hairline so
/// white-on-near-white still reads as a card in light mode.
abstract final class HomeSurface {
  /// Card fill: the theme surface (white / #15191D in Plan F), a step up
  /// from the page background in both brightnesses.
  static Color fill(bool dark) =>
      dark ? AppColors.surfaceDark : AppColors.surfaceLight;

  /// Hairline around the card (quiet; decorative).
  static Color rim(bool dark) =>
      (dark ? AppColors.borderDark : AppColors.borderLight).withValues(
        alpha: dark ? 0.7 : 0.55,
      );

  /// Corner radius of tiles and context cards (16).
  static const double radius = AppSpacing.radiusLg;

  static BoxDecoration decoration(bool dark) => BoxDecoration(
    color: fill(dark),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: rim(dark)),
  );
}

/// The 3D clay illustrations the Home screen ships
/// (assets/home/ + assets/home_dark/, cropped from the Blender clay renders).
abstract final class HomeArt {
  /// Service tiles.
  static const String ride = 'ride';
  static const String prebook = 'prebook';
  static const String someoneElse = 'someone_else';
  static const String saved = 'saved';

  /// Extra art for promo banners.
  static const String addStop = 'add_stop';
  static const String coins = 'coins';
  static const String star = 'star';
  static const String tag = 'tag';

  /// Every key with a light and a dark render.
  static const List<String> keys = [
    ride,
    prebook,
    someoneElse,
    saved,
    addStop,
    coins,
    star,
    tag,
  ];

  /// Asset path for [key] in the given brightness.
  static String path(String key, {required bool dark}) =>
      'packages/design_system/assets/${dark ? 'home_dark' : 'home'}/$key.png';
}

/// A square 3D clay illustration by [HomeArt] key; decorative (excluded
/// from semantics — the tile/banner around it carries the label). Picks the
/// dark render in dark mode. An unknown key or missing file paints nothing
/// rather than breaking the layout.
class HomeArtImage extends StatelessWidget {
  const HomeArtImage(this.art, {super.key, this.size = 56});

  final String art;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: Image.asset(
        HomeArt.path(art, dark: dark),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
      ),
    );
  }
}
