import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'lottie_moment.dart';

/// Full-width primary CTA with a built-in loading state, a tactile press-scale,
/// and a light haptic on tap. One primary action per screen — this is it.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  /// Red instead of brand green, for irreversible actions (e.g. deleting an
  /// account). Still the one primary action on its screen.
  final bool destructive;

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
    // Depend on the theme: the ink colours below must follow a light/dark
    // switch made while the app is open.
    Theme.of(context);
    final w = widget;
    final enabled = w.onPressed != null && !w.loading;
    // accentInk (not accent) so the white label clears WCAG AA (5.2:1);
    // errorInk likewise (6.6:1).
    // Read the brightness from this widget's own context rather than the
    // global AppColors flag. That flag is written once per frame from
    // MaterialApp.builder, so a button that builds before the builder has run
    // for the new brightness paints with the previous one — on iOS that showed
    // up as a black CTA on the near-black dark sheet. Theme.of also registers a
    // dependency, so the button repaints when the brightness changes.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill =
        w.destructive ? AppColors.errorInk : AppColors.inkFor(dark);
    final onFill = w.destructive ? AppColors.white : AppColors.onInkFor(dark);
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      child: SizedBox(
        width: double.infinity,
        height: AppSpacing.buttonHeight,
        child: FilledButton(
          statesController: _states,
          style: FilledButton.styleFrom(
            backgroundColor: fill,
            disabledBackgroundColor: fill.withValues(alpha: 0.4),
            foregroundColor: onFill,
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
                // The brand arc, in the button's ink (payment, confirm…).
                ? SizedBox(
                    key: ValueKey('loading'),
                    height: 26,
                    width: 26,
                    child: LottieMoment.spinner(size: 26, tint: onFill),
                  )
                : Row(
                    key: const ValueKey('label'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (w.icon != null) ...[
                        Icon(w.icon, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      // Long labels ("Confirm Economy · $7.33" on a 360dp
                      // phone) ellipsize instead of overflowing the button.
                      Flexible(
                        child: Text(w.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
