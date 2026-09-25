import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'app_modal_sheet.dart';
import 'theme_controller.dart';

/// Light / Dark / Same as phone — the Appearance picker.
Future<void> showAppearanceSheet(
  BuildContext context,
  ThemeController controller,
) {
  return showAppModalSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: controller,
          builder: (ctx, mode, _) => RadioGroup<ThemeMode>(
            groupValue: mode,
            onChanged: (v) {
              if (v != null) controller.set(v);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Appearance', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                for (final (m, icon, hint) in const [
                  (
                    ThemeMode.system,
                    PhosphorIconsRegular.circleHalf,
                    'Follows your phone\'s setting',
                  ),
                  (ThemeMode.light, PhosphorIconsRegular.sun, 'Always light'),
                  (
                    ThemeMode.dark,
                    PhosphorIconsRegular.moon,
                    'Always dark, easier at night',
                  ),
                ])
                  RadioListTile<ThemeMode>(
                    value: m,
                    secondary: Icon(icon),
                    title: Text(ThemeController.label(m)),
                    subtitle: Text(hint),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
