import 'package:flutter/material.dart';
import '../theme/phosphor_icons.dart';

import '../theme/app_colors.dart';

/// Circular avatar showing initials (from [name]) or a fallback [icon] on a
/// tinted brand background. Consistent across driver cards, profiles, chat.
/// When [imageUrl] is set the photo is shown over that, and the initials stay
/// underneath while it loads or if it fails.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.name,
    this.icon,
    this.size = 44,
    this.color,
    this.imageUrl,
  });

  final String? name;
  /// Optional photo (e.g. the driver's). Blank/null means initials only.
  final String? imageUrl;
  final IconData? icon;
  final double size;
  /// Defaults to the theme's ink colour.
  final Color? color;

  String get _initials {
    final parts =
        (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // Depend on the theme: the ink colours below must follow a light/dark
    // switch made while the app is open.
    Theme.of(context);
    final initials = _initials;
    final url = imageUrl?.trim();
    final base = _base(initials);
    if (url == null || url.isEmpty) return base;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          base,
          ClipOval(
            child: Image.network(
              url,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _base(String initials) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: (color ?? AppColors.accent).withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: initials.isNotEmpty
          ? Text(
              initials,
              style: TextStyle(
                color: color ?? AppColors.accent,
                fontSize: size * 0.38,
                fontWeight: FontWeight.w700,
              ),
            )
          : Icon(icon ?? PhosphorIconsRegular.user, color: color ?? AppColors.accent, size: size * 0.5),
    );
  }
}
