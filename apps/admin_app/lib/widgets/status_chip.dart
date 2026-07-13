import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// A small colored pill for a trip status.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});
  final String status;

  Color get _color => switch (status) {
        'completed' => AppColors.success,
        'in_progress' => AppColors.accent,
        'accepted' || 'arrived' => AppColors.warning,
        'requested' || 'matching' => Colors.blueGrey,
        'cancelled' || 'no_drivers' || 'expired' => AppColors.error,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
