import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Full-width primary CTA with a built-in loading state, a tactile press-scale,
/// and a light haptic on tap. One primary action per screen — this is it.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  final WidgetStatesController _states = WidgetStatesController();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(() {
      final down = _states.value.contains(WidgetState.pressed);
      if (down != _pressed) setState(() => _pressed = down);
    });
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final enabled = w.onPressed != null && !w.loading;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton(
          statesController: _states,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.4),
            foregroundColor: AppColors.onAccent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            textStyle: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
          onPressed: enabled
              ? () {
                  AppHaptics.light();
                  w.onPressed!();
                }
              : null,
          child: AnimatedSwitcher(
            duration: AppMotion.fast,
            child: w.loading
                ? const SizedBox(
                    key: ValueKey('loading'),
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation(AppColors.onAccent),
                    ),
                  )
                : Row(
                    key: const ValueKey('label'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (w.icon != null) ...[
                        Icon(w.icon, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Text(w.label),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
