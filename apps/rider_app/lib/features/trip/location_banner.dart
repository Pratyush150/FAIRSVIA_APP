import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'location_service.dart';

/// What the location banner asks the rider to do when tapped.
enum LocationBannerAction {
  /// Re-run the permission prompt / GPS read (soft denial, transient error).
  retry,

  /// Open the app's Settings page (permission denied forever, precise off).
  openAppSettings,

  /// Open the device's Location Services toggle.
  openLocationSettings,
}

/// Persistent, tappable strip under the status bar telling the rider why
/// their position is unknown (or approximate) and how to fix it. Hidden when
/// there's nothing to report. Styled like [ConnectionBanner] so the two stack
/// naturally.
class LocationBanner extends StatelessWidget {
  const LocationBanner({
    super.key,
    required this.issue,
    required this.reducedAccuracy,
    required this.onAction,
  });

  final LocationIssue? issue;
  final bool reducedAccuracy;
  final ValueChanged<LocationBannerAction> onAction;

  bool get visible => issue != null || reducedAccuracy;

  /// The message for a given state (null = nothing to show).
  static String? messageFor(LocationIssue? issue, bool reducedAccuracy) {
    switch (issue) {
      case LocationIssue.servicesOff:
        return 'Location is off — tap to enable';
      case LocationIssue.denied:
        return 'Location permission needed — tap to allow';
      case LocationIssue.deniedForever:
        return 'Location access denied — tap to open Settings';
      case LocationIssue.error:
        return "Couldn't get your location — tap to retry";
      case null:
        break;
    }
    if (reducedAccuracy) {
      return 'Precise Location is off — turn it on in Settings for an '
          'accurate pickup';
    }
    return null;
  }

  static LocationBannerAction actionFor(
    LocationIssue? issue,
    bool reducedAccuracy,
  ) {
    switch (issue) {
      case LocationIssue.servicesOff:
        return LocationBannerAction.openLocationSettings;
      case LocationIssue.deniedForever:
        return LocationBannerAction.openAppSettings;
      case LocationIssue.denied:
      case LocationIssue.error:
        return LocationBannerAction.retry;
      case null:
        return LocationBannerAction.openAppSettings; // precise-location off
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = messageFor(issue, reducedAccuracy);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              container: true,
              button: true,
              label: message,
              child: Material(
                color: AppColors.warning,
                child: InkWell(
                  onTap: () => onAction(actionFor(issue, reducedAccuracy)),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_off_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              message,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
