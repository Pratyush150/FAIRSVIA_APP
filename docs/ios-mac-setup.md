# iOS build & test — Mac setup

> **Status (validated 2026-08-04, Mac + Xcode 26.6, iOS 26.5/18.5 simulators):**
> both apps build and run on the iOS Simulator. Full rider+driver E2E validated
> on two simulators against a Mac-local backend (Homebrew Postgres 16 + Redis,
> `npm run start:dev`, stub geo provider): signup → destination → tiers → book →
> dispatch offer → accept → arrive → 4-digit start code → live tracking → chat →
> complete → tip → rate → receipt, plus cancellation, SOS sheet, mock add-card,
> payment methods, trip history, and dark mode. Use
> `--dart-define=MOCK_LOCATION=25.7743,-80.1937` on simulators (Apple's default
> GPS fix is Cupertino, which breaks the Florida-only fare estimates).

iOS cannot be compiled on the Linux dev server (no Xcode). This is the checklist
to build + run the two mobile apps on a Mac. Everything here is committed
iOS-ready; the steps below are the Mac-only actions that can't run on Linux.

## Prerequisites
- macOS + Xcode (latest), CocoaPods (`sudo gem install cocoapods`).
- Flutter on the Mac (same channel as the server: stable 3.44.x).
- Clone the repo, then from the repo root: `flutter pub get`.

## Per-app first build
For each of `apps/rider_app` and `apps/driver_app`:

```bash
cd apps/rider_app        # then repeat for apps/driver_app
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace   # set your signing Team on the Runner target, once
flutter run -d "iPhone 15"    # or any booted simulator; no physical device needed
```

Notes:
- **iOS deployment target is 15.0** (Google Maps SDK floor; flutter_stripe and
  geolocator need ≥13). If `pod install` complains, confirm `ios/Podfile` has
  `platform :ios, '15.0'`.
- If CocoaPods can't resolve the Stripe frameworks, add `use_frameworks!` and
  `use_modular_headers!` inside the `target 'Runner'` block of the Podfile
  (flutter_stripe guidance) and re-run `pod install`.

## What's already configured (committed)
- `Info.plist` (both apps): `NSLocationWhenInUseUsageDescription` (geolocator
  would otherwise fail at runtime) and a `ubernav://` URL scheme
  (`CFBundleURLTypes`) for the Stripe / Connect return deep links.
- `IPHONEOS_DEPLOYMENT_TARGET = 15.0`.

## Maps (Google Maps SDK — key required)
The map is **Google Maps** (`google_maps_flutter`) on both platforms. Without a
key the map view initialises (Google logo, markers and route lines draw) but
the basemap tiles stay blank. Put the key in the gitignored native secrets:

- iOS: `apps/<app>/ios/Flutter/Secrets.xcconfig` → `MAPS_API_KEY=AIza…`
  (Debug/Release.xcconfig `#include?` it; Info.plist `GMSApiKey` = `$(MAPS_API_KEY)`;
  `AppDelegate.swift` calls `GMSServices.provideAPIKey`).
- Android: `apps/<app>/android/secrets.properties` → `MAPS_API_KEY=AIza…`.

Enable "Maps SDK for iOS" (and "Maps SDK for Android") on the key in Google
Cloud Console. **Deployment floor is iOS 15.0** (GoogleMaps 9.x) — the Podfile
and Xcode project are already set; keep them in sync.

## Validated on a Mac (2026-09-10)
Xcode 26.6 / iOS 26.5 simulators / Flutter 3.44.6 / CocoaPods 1.17.0. Both apps
build and run; full rider→driver ride (signup, search, estimate, offer,
accept, start code, complete, tip/rate), card + cash, cancellation, dark
mode, account pages exercised on iPhone 17 + iPhone 16 Pro simulators.

Gotchas hit on the way:
- A fresh Xcode 26 may have **no iOS Simulator runtime** (`xcrun simctl list
  runtimes` empty; Flutter says "iOS 26.5 is not installed"). Fix:
  `xcodebuild -downloadPlatform iOS` (~8.5 GB).
- `pod install` adds Pods refs to `project.pbxproj`, the workspace, and the
  `Pods-Runner.*.xcconfig` includes in `Flutter/Debug|Release.xcconfig`;
  those (plus `Podfile.lock` / `Package.resolved`) are committed.
- Simulator UI automation: `idb ui tap X Y --duration 0.05` (taps without
  `--duration` are silently dropped on iOS 26), `idb ui text`, `idb ui key 40`
  (Enter) / `43` (Tab); coordinates are points (px / 3 on iPhone 17).
  Screenshots: `xcrun simctl io <udid> screenshot out.png`.
- Run with `--dart-define=MOCK_LOCATION=25.7743,-80.1937` (Miami) or the
  simulator's default Cupertino fix produces 3,000-mile fares.

## Stripe on the client
- The **publishable key is fetched from the backend at runtime** (in the
  `/payments/setup-intent` response) and applied right before the PaymentSheet
  is shown — there is no build-time Stripe key to set on the client.
- Until `STRIPE_SECRET_KEY` + `STRIPE_PUBLISHABLE_KEY` are set on the backend,
  the app runs the **mock** add-card flow (brand + last-4); it flips to the real
  native PaymentSheet automatically once those keys are present.

## Can't be done on Linux (do on the Mac)
- Compile/run/screenshot iOS (simulator is fine — no physical iPhone needed for
  signup / ride / payments / dark-mode flows).
- A physical iPhone is only needed for real GPS, camera, or live push.
