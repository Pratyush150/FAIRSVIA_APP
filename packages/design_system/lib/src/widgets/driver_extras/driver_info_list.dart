import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/phosphor_icons.dart';

/// A titled block on the driver's pulled-up sheet: a small header (with an
/// optional trailing action) over its content.
class DriverExtraSection extends StatelessWidget {
  const DriverExtraSection({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

/// One row of a [DriverInfoList]: icon, title, a line of detail, and an
/// optional tap (drawn with a chevron).
class DriverInfoItem {
  const DriverInfoItem({
    required this.icon,
    required this.title,
    this.detail,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onTap;

  /// Short right-aligned text ("1.2 km").
  final String? trailing;
}

/// A soft card of icon rows (busy areas, how-it-works tips, help links).
class DriverInfoList extends StatelessWidget {
  const DriverInfoList({super.key, required this.items});

  final List<DriverInfoItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final divider = theme.dividerColor.withValues(alpha: 0.4);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(
            color: dark ? AppColors.borderDark : AppColors.borderLight),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: divider),
              _Row(item: items[i], dark: dark),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.dark});

  final DriverInfoItem item;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: item.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.softFor(dark),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon,
                    size: 18, color: AppColors.accentTextFor(dark)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: theme.textTheme.titleSmall),
                    if (item.detail != null) ...[
                      const SizedBox(height: 2),
                      Text(item.detail!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (item.trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(item.trailing!, style: theme.textTheme.labelLarge),
              ],
              if (item.onTap != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(PhosphorIconsRegular.caretRight,
                    size: 16, color: AppColors.iconNeutralFor(dark)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
