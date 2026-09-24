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
                  child: Text(
                    status.title,
                    // Keyed on the text so the switcher animates when the
                    // wording changes ("on the way" → "almost here") and
                    // stays put when only the minute count moves.
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
