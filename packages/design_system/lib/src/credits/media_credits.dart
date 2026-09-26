import 'package:flutter/foundation.dart';

/// Attribution for bundled media whose licence requires it (CC BY), shown on
/// the in-app "Credits & licences" page (Flutter's license page). Full source
/// list: docs/brand/CREDITS-ride-vehicles.md and the assets' CREDITS.md files.
const List<String> mediaCredits = [
  '"White Opel Karl side view" by Renée Kools, licensed CC BY 4.0 '
      '(https://creativecommons.org/licenses/by/4.0/), via Wikimedia Commons; '
      'modified (background removed, logos painted out, resized). '
      'Used for the Economy ride picture.',
  'Other vehicle, Home and poster photos: Unsplash (Unsplash License). '
      'Animations: LottieFiles (Lottie Simple License).',
];

bool _registered = false;

/// Adds [mediaCredits] to the license registry once; safe to call repeatedly.
void registerMediaCredits() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() => Stream.value(
        LicenseEntryWithLineBreaks(
          const ['RideVela artwork'],
          mediaCredits.join('\n\n'),
        ),
      ));
}
