import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Semantic tone for a [AppStatusChip].
enum StatusTone { neutral, success, warning, error, info, accent }

/// A compact status pill — tinted background, colored label. One implementation
/// to replace the status pills reinvented across admin, support, and history.
class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  Color get _base {
    switch (tone) {
      case StatusTone.success:
        return AppColors.success;
      case StatusTone.warning:
        return AppColors.warning;
      case StatusTone.error:
        return AppColors.error;
      case StatusTone.info:
        return AppColors.info;
      case StatusTone.accent:
        return AppColors.accent;
      case StatusTone.neutral:
        return AppColors.textTertiaryLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Caution as text needs the deeper ochre / bright amber to reach 4.5:1;
    // the tint behind it keeps the brand ochre.
    final c = tone == StatusTone.warning
        ? AppColors.warningTextOf(context)
        : _base;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: c),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
