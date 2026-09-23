import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Circular avatar showing initials (from [name]) or a fallback [icon] on a
/// tinted brand background. Consistent across driver cards, profiles, chat.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.name,
    this.icon,
    this.size = 44,
    this.color,
  });

  final String? name;
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
          : Icon(icon ?? Icons.person_rounded, color: color ?? AppColors.accent, size: size * 0.5),
    );
  }
}
