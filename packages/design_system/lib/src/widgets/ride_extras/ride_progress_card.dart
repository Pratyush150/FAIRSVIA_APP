import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../app_card.dart';

/// A live ride's progress at a glance: a caption ("Trip progress"), the
/// headline figures ("4.1 km · 12 min left"), an arrival line ("Arriving
/// 3:42 PM") and, when [progress] is known, a bar from [startLabel] to
/// [endLabel]. Every value is the caller's: nothing here invents a number,
/// and a missing one simply leaves its line out.
class RideProgressCard extends StatelessWidget {
  const RideProgressCard({
    super.key,
    required this.title,
    required this.headline,
    this.arrival,
    this.progress,
    this.startLabel,
    this.endLabel,
    this.icon,
    this.glyph,
    this.endGlyph,
  });

  final String title;
  final String headline;

  /// "Arriving 3:42 PM"; null leaves the line out.
  final String? arrival;

  /// 0..1 along the leg; null hides the bar (e.g. no total known).
  final double? progress;
  final String? startLabel;
  final String? endLabel;
  final IconData? icon;

  /// Drawn riding along the bar at [progress] (e.g. a car on the trip), and
  /// glides to each new value. Null keeps the plain bar.
  final IconData? glyph;

  /// Drawn at the far end of the bar (e.g. a pickup pin the car glides
  /// toward). Only with [glyph]; null leaves the end bare.
  final IconData? endGlyph;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted =
        dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final p = progress?.clamp(0.0, 1.0);
    return AppCard(
      child: Semantics(
        container: true,
        label: [
          title,
          headline,
          ?arrival,
          if (p != null) '${(p * 100).round()} percent of the way',
        ].join('. '),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.accent),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: muted)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              headline,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            if (arrival != null)
              Text(arrival!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            if (p != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _TrackWithGlyph(
                progress: p,
                glyph: glyph,
                endGlyph: endGlyph,
                track: theme.dividerColor,
              ),
            ],
            if (startLabel != null || endLabel != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(startLabel ?? '',
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(endLabel ?? '',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The progress bar, animated: the fill (and [glyph], when given) glides to
/// each new [progress] instead of jumping. One-shot tweens, so tests settle;
/// Reduce Motion snaps straight to the value.
class _TrackWithGlyph extends StatelessWidget {
  const _TrackWithGlyph({
    required this.progress,
    required this.glyph,
    required this.track,
    this.endGlyph,
  });

  final double progress;
  final IconData? glyph;
  final IconData? endGlyph;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    const glyphSize = 22.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final bar = ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.pill),
          child: LinearProgressIndicator(
            key: const ValueKey('ride-progress-bar'),
            value: v,
            minHeight: 6,
            color: AppColors.accent,
            backgroundColor: track,
          ),
        );
        if (glyph == null) return bar;
        return SizedBox(
          height: glyphSize + 4,
          child: LayoutBuilder(
            builder: (context, c) {
              final x = (c.maxWidth - glyphSize) * v;
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  bar,
                  if (endGlyph != null)
                    Positioned(
                      right: 0,
                      child: Icon(
                        endGlyph,
                        key: const ValueKey('ride-progress-end-glyph'),
                        size: glyphSize,
                        color: AppColors.accent,
                      ),
                    ),
                  Positioned(
                    left: x,
                    child: Container(
                      key: const ValueKey('ride-progress-glyph'),
                      width: glyphSize,
                      height: glyphSize,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(glyph, size: 14, color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
