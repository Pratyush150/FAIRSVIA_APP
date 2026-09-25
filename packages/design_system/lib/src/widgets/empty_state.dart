import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Friendly empty/placeholder state: a soft icon medallion (or [art], e.g. a
/// LottieMoment such as `LottieMoment.emptyBox()`), a title, an optional
/// line of guidance, and an optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.art,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// Illustration shown instead of the [icon] medallion (the icon is then
  /// unused). Keep it decorative: the title says what it means.
  final Widget? art;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (art != null)
              art!
            else
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: AppColors.accent),
              ),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
