import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A chat bubble. `mine` = brand-filled, right-aligned; otherwise a muted
/// surface bubble, left-aligned. One implementation for the in-trip chat,
/// support thread, and admin console.
class AppMessageBubble extends StatelessWidget {
  const AppMessageBubble({
    super.key,
    required this.text,
    required this.mine,
    this.caption,
  });

  final String text;
  final bool mine;

  /// Optional line under the bubble (timestamp / author).
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final radius = Radius.circular(AppSpacing.radius);
    final bg = mine
        ? AppColors.accent
        : (isDark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight);
    final fg = mine
        ? AppColors.onAccent
        : theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.74,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: radius,
              topRight: radius,
              bottomLeft: mine ? radius : const Radius.circular(4),
              bottomRight: mine ? const Radius.circular(4) : radius,
            ),
          ),
          child: Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(color: fg, height: 1.3),
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Text(caption!, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}
