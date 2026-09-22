# Handoff — building RideVela on a Mac

For whoever opens this repo on a Mac to build and run the iOS apps.

> **Corrected 2026-09-22.** An earlier version of this file said iOS had never
> been compiled, that no Podfile existed, and that no Google Maps key was
> needed. All three were stale and the last one would have cost you an hour
> staring at a blank grey map. What follows was checked against the tree.

## Honest state

| | |
|---|---|
| **iOS** | **Has been compiled and run on a Mac** — Xcode 26.6, Flutter 3.44.6, on iPhone 17 + iPhone 16 Pro **simulators** (see `docs/changelog-ios-validation-2026-09-10.md` and `docs/ios-audit-report-2026-09-14.md`). **Never run on a physical iPhone.** Not rebuilt since 2026-09-14. |
| **Android** | Fully validated, real headless emulator, continuously. |
| **Maps** | **Google Maps SDK.** `flutter_map` is still in pubspec but the live map is `google_maps_flutter`. **iOS needs an API key** — see below. |
| **Stripe** | Real **test** keys are set. `STRIPE_WEBHOOK_SECRET` is **not**, so payments authorise and capture but webhooks are rejected and never reach a final state. |
| **Backend** | Docker on the Linux box. Its LAN IP is DHCP and has moved before — get it with `hostname -I` on that box (currently `192.168.1.69`). |

## Changes since the last iOS build (2026-09-14)

All Dart and backend. **Nothing touched the Xcode project, the Podfile or any
native iOS code** — the only files changed under `ios/` are the two
`Info.plist`s, and only their brand strings (FairsVia → RideVela).

So this should build. It has not been proven to, because there is no Mac here.

## Before you build — the two things that will bite

**1. The Google Maps key.** `Info.plist` reads `$(MAPS_API_KEY)`, which comes
from `ios/Flutter/Secrets.xcconfig` — gitignored, so it is not in your
checkout. Without it the app launches and the map renders **blank grey with no
error**. Create it for each app:

```bash
for app in rider_app driver_app; do
  echo 'MAPS_API_KEY=YOUR_IOS_MAPS_KEY' > apps/$app/ios/Flutter/Secrets.xcconfig
done
```

The key needs **Maps SDK for iOS** enabled, and its iOS-app restriction must
list the bundle ids (`in.novarobotics.ubernav.rider`, `...driver`) or be
unrestricted for testing.

**2. The backend URL.** Release builds *refuse to start* without an explicit
`API_BASE_URL`, and reject `localhost`. The Mac and the iPhone must be on the
same Wi-Fi as the Linux box:

```bash
flutter run -d <device> \
  --dart-define=API_BASE_URL=http://192.168.1.69:3000/api/v1
```

ATS already allows plain HTTP (`NSAllowsArbitraryLoads`), so the LAN backend
works. **That flag must come out before any App Store submission.**

## Build

```bash
flutter pub get
(cd apps/rider_app/ios && pod install)
(cd apps/driver_app/ios && pod install)

# Simulator — no signing needed
cd apps/rider_app
flutter run -d "iPhone 16" --dart-define=API_BASE_URL=http://192.168.1.69:3000/api/v1
```

For a **physical iPhone**, open `Runner.xcworkspace` once and set a Signing
Team. `Podfile.lock` is committed, so `pod install` should resolve exactly what
the last successful build used.

## What to test first

The field checklist is `docs/field-testing-plan.md` — 23 cases, ordered, with a
pass/fail column. Section 1 blocks launch.

Two things to watch specifically, because they are **fixed but never verified
on iOS**:

- **Pinch-to-zoom during a live ride.** Zooming must not stop the map following
  the car; panning must, and must raise a "Recenter" pill. Verified on Android;
  the gesture classifier is shared Dart, but iOS reports camera events on
  slightly different timing.
- **Background the app mid-ride, then reopen.** The camera and the trip state
  should both resync to the live driver position. iOS suspends the WebSocket
  more aggressively than Android, so this is the iOS-specific risk.

## Known, deliberate

- `NSAllowsArbitraryLoads` is on (LAN HTTP). Blocks App Store review.
- The URL schemes are still `fairsvia-rider://` / `fairsvia-driver://`. They are
  registered identifiers tied to the Stripe Connect return URLs, not branding —
  renaming them breaks the Connect flow.
- `flutter_map` remains a dependency; it is not what draws the live map.
