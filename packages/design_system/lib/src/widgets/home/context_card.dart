import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import 'home_art.dart';
import 'press_scale.dart';

/// A generic Home card slot — "Rate your ride with Ravi", the active ride,
/// an offer: [leading] (avatar, art, icon badge), a title, an optional
/// subtitle and an optional [trailing] (button, chevron, chip). Surface a
/// step lighter than the page, radius 16, 16 dp padding.
class ContextCard extends StatelessWidget {
  const ContextCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.semanticLabel,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Overrides the spoken label (defaults to "[title]. [subtitle]").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(HomeSurface.radius);

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            ExcludeSemantics(child: leading),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.md),
              trailing!,
            ],
          ],
        ),
      ),
    );

    final card = Material(
      color: Colors.transparent,
      child: Ink(
        decoration: HomeSurface.decoration(dark),
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: radius, child: content),
      ),
    );

    if (onTap == null) {
      return Semantics(container: true, label: semanticLabel, child: card);
    }
    return Semantics(
      button: true,
      container: true,
      label: semanticLabel,
      child: PressScale(
        scale: 0.96,
        rim: true,
        glow: PressScale.brandGlow(dark),
        glowRadius: radius,
        child: card,
      ),
    );
  }
}
