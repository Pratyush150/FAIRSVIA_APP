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
    this.color = AppColors.accent,
  });

  final String? name;
  final IconData? icon;
  final double size;
  final Color color;

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
    final initials = _initials;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: initials.isNotEmpty
          ? Text(
              initials,
              style: TextStyle(
                color: color,
                fontSize: size * 0.38,
                fontWeight: FontWeight.w700,
              ),
            )
          : Icon(icon ?? Icons.person_rounded, color: color, size: size * 0.5),
    );
  }
}
