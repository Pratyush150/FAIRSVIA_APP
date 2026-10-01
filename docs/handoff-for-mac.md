# Handoff — building FAIRSVIA on a Mac

> **2026-09-23: start with [mac-ios-pilot-handoff.md](mac-ios-pilot-handoff.md)** —
> the Pune pilot build, the exact iPhone checklist, and what changed. Where
> the two disagree, that file wins.

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

### The camera rules, and what has actually been proven

The intended behaviour: **any** deliberate pan, drag or zoom pauses automatic
following and raises a "◎ Recenter" pill. Tapping it returns the camera to the
live driver position, restores street-level zoom, and resumes following.

Verified on Android, by hand, against a live crawling ride
(`tools/fake-driver-simulator/slow-ride.mjs`):

| Step | Result |
|---|---|
| Baseline | car tracked, route ahead drawn, no pill |
| Drag the map away | following suspended, pill raised, car off-screen |
| Tap Recenter | camera back on the car, pill gone |
| Zoom (double-tap) | following suspended, pill raised |
| Tap Recenter | camera back on the car **and** zoom restored |
| Wait 45 s untouched | car moved, stayed framed, no pill — following genuinely active |

**Not verified anywhere:** a true two-finger **pinch**. `adb` cannot drive
multitouch, so the pinch path is covered only by the unit test on
`AppMap.isUserGesture`. On iOS, check it by hand — pinch during a live ride
should raise the pill exactly as the double-tap does.

**The iOS-specific risk: background the app mid-ride, then reopen.** The camera
and the trip state should both resync to the live driver position. iOS suspends
the WebSocket far more aggressively than Android, so this is the one most
likely to behave differently.

## Known, deliberate

- `NSAllowsArbitraryLoads` is on (LAN HTTP). Blocks App Store review.
- The URL schemes are still `fairsvia-rider://` / `fairsvia-driver://`. They are
  registered identifiers tied to the Stripe Connect return URLs, not branding —
  renaming them breaks the Connect flow.
- `flutter_map` remains a dependency; it is not what draws the live map.
