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
- **iOS deployment target is already 13.0** in the Xcode project — required by
  flutter_stripe. If `pod install` ever complains, confirm the generated
  `ios/Podfile` has `platform :ios, '13.0'`.
- If CocoaPods can't resolve the Stripe frameworks, add `use_frameworks!` and
  `use_modular_headers!` inside the `target 'Runner'` block of the Podfile
  (flutter_stripe guidance) and re-run `pod install`.

## What's already configured (committed)
- `Info.plist` (both apps): `NSLocationWhenInUseUsageDescription` (geolocator
  would otherwise fail at runtime) and a `ubernav://` URL scheme
  (`CFBundleURLTypes`) for the Stripe / Connect return deep links.
- `IPHONEOS_DEPLOYMENT_TARGET = 13.0`.

## Maps
The map uses **`flutter_map` (OpenStreetMap tiles)** — there is **no
google_maps_flutter dependency**, so **no Google Maps API key is required** to
render maps on iOS or Android. (Any Google key you provide would only be for
optional server-side Places/Directions, not the map view, which uses the
self-hosted OSRM/Nominatim stack.)

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
