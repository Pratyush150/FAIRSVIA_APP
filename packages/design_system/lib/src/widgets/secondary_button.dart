import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_ink.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Full-width secondary action — outlined, same height/rhythm as [PrimaryButton].
/// Use for the lesser of two side-by-side actions, or a standalone alt action.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = danger
        ? AppColors.error
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);
    // Uber-style secondary action: a quiet grey fill, no outline.
    // Plan E (THEME=ink): no fill — an ink outline on the paper (the
    // outline token, 3.3:1, since it is the control's only edge).
    final fill = InkPaper.on
        ? Colors.transparent
        : danger
        ? (isDark ? AppColors.errorSoftDark : AppColors.errorSoft)
        : (isDark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight);
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.buttonHeight,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: fill,
          disabledForegroundColor: fg.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            side: InkPaper.on
                ? BorderSide(
                    color: danger ? fg : InkPaper.outline(isDark), width: 1)
                : BorderSide.none,
          ),
          // The family must be named here: a button's textStyle replaces the
          // theme's, and without it the label fell back to the platform font.
          textStyle: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: onPressed == null
            ? null
            : () {
                AppHaptics.light();
                onPressed!();
              },
        // Scale the content down rather than overflow when the button is
        // given a narrow slot (e.g. beside a primary action in a Row).
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
