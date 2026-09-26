import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'ride_status.dart';

/// The headline block at the top of every live-ride sheet: what is happening,
/// and the number under it.
///
/// One widget for all the ride states so the type scale, the spacing and the
/// transition are identical as the ride moves through them — the sheet reads
/// as one surface changing its mind, not a stack of different cards. The text
/// cross-fades on the standard motion tokens; the numeric sub-line uses
/// tabular figures so a ticking ETA doesn't shuffle sideways.
///
/// The headline is a screen-reader live region (audit 4.3): when the moment
/// changes — "Priya is on the way" → "Priya has arrived" — TalkBack and
/// VoiceOver announce it without the rider having to find it. The region's
/// label is [RideStatus.moment], which leaves the minute count out (it rides
/// along as the node's value), so a reader hears each change of moment and
/// not every tick of the ETA.
class RideStatusHeader extends StatelessWidget {
  const RideStatusHeader({
    super.key,
    required this.status,
    this.trailing,
    this.detail,
  });

  final RideStatus status;

  /// Optional control pinned to the right of the headline (SOS, chat).
  final Widget? trailing;

  /// An extra muted line under the sub-line (e.g. the destination).
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // One node carrying the current wording: the switcher briefly
              // holds the old and new Text during the cross-fade, and a
              // reader must hear only the new one.
              Semantics(
                container: true,
                liveRegion: true,
                header: true,
                label: status.moment,
                value: status.momentDetail,
                excludeSemantics: true,
                child: AnimatedSwitcher(
                  duration: AppMotion.normal,
                  switchInCurve: AppMotion.enter,
                  switchOutCurve: AppMotion.exit,
                  // Keyed on the text so the switcher animates when the
                  // wording changes ("on the way" → "almost here") and
                  // stays put when only the minute count moves.
                  child: InkPaper.on
                      // THEME=ink: the status headline is a serif moment,
                      // with balanced lines ("Rahul arriving / in 3 min").
                      ? BalancedText(
                          status.displayTitle,
                          key: ValueKey(status.title),
                          style: theme.textTheme.headlineSmall?.serifMoment(32),
                        )
                      : _UnbrokenTitle(
                          status.displayTitle,
                          key: ValueKey(status.title),
                          style: theme.textTheme.headlineSmall,
                        ),
                ),
              ),
              if (status.subtitle case final sub?) ...[
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: AppMotion.fast,
                  child: Text(
                    sub,
                    key: ValueKey(sub),
                    style: theme.textTheme.titleMedium?.tabular().copyWith(
                      color: _toneColor(context, status.tone),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (detail case final d?) ...[
                const SizedBox(height: AppSpacing.xs),
                d,
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  static Color? _toneColor(BuildContext context, RideStatusTone tone) {
    switch (tone) {
      case RideStatusTone.success:
        return AppColors.accentText;
      case RideStatusTone.accent:
        return AppColors.accentText;
      case RideStatusTone.neutral:
        return Theme.of(context).textTheme.bodyMedium?.color;
    }
  }
}

/// The headline, never broken inside its non-breaking ETA phrase.
///
/// [RideStatus.displayTitle] glues "arriving in 9 min" together so it wraps
/// as a unit. If even that unit is wider than the line (a 360 dp phone at
/// 1.3× text), Flutter would split it character by character; instead the
/// size steps down just enough for the longest unbroken run to fit, so the
/// title stays at most "Name / arriving in 9 min".
class _UnbrokenTitle extends StatelessWidget {
  const _UnbrokenTitle(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final base = DefaultTextStyle.of(context).style.merge(style);
        var fitted = base;
        final maxWidth = constraints.maxWidth;
        final size = base.fontSize;
        if (maxWidth.isFinite && size != null) {
          final scaler = MediaQuery.textScalerOf(context);
          // The widest run the line breaker may not split.
          var widest = 0.0;
          for (final run in text.split(' ')) {
            final painter = TextPainter(
              text: TextSpan(text: run, style: base),
              textDirection: Directionality.of(context),
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            if (painter.width > widest) widest = painter.width;
            painter.dispose();
          }
          if (widest > maxWidth) {
            // Floor, not round: a half pixel over still splits the run.
            fitted = base.copyWith(
              fontSize: (size * maxWidth / widest * 100).floorToDouble() / 100,
            );
          }
        }
        return Text(text, style: fitted);
      },
    );
  }
}
