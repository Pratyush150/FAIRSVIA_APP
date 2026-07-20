# Handoff — Mac-side Claude Code session

You are a fresh Claude Code session on the user's **Mac**. This project was built
on a Linux server that cannot compile iOS. Your job: build + run the apps on iOS
(Simulator first, then the user's **physical iPhone 14**) and help the user test.
Read `docs/ios-mac-setup.md` too.

## Project in one line
UberNav — Uber-style ride-hailing: Flutter monorepo (`apps/rider_app`,
`apps/driver_app`, `apps/admin_app` [web]; shared `packages/core`,
`design_system`, `shared_models`) + a NestJS/Postgres/PostGIS/Redis backend.

## Current state (honest)
- **Android:** fully validated end-to-end (real phone + emulator). Builds green.
- **iOS:** code is iOS-ready but has **NEVER been compiled** — this is the task.
  No Podfile exists yet; `flutter` generates it on first build.
- **Payments (Stripe):** code-complete but running on the **mock path** — the
  Stripe keys in `backend/.env` are empty. Real PaymentSheet/charge/payout only
  activate once `STRIPE_SECRET_KEY` + `STRIPE_PUBLISHABLE_KEY` (test) are set.
  The rider app falls back to a mock add-card sheet until then — expected.
- **Map:** uses `flutter_map` (OpenStreetMap). **No Google Maps key needed.**

## Backend connectivity
The backend runs in Docker on the Linux box at **`192.168.1.48:3000/api/v1`**.
The Mac + iPhone must be on the **same Wi-Fi** to reach it. Confirm the app's
configured API base URL points there (check `packages/core` network config). If
unreachable, either fix the base URL or run the backend on the Mac via
`infra/docker-compose.yml`.

## Build steps (per app: rider_app, then driver_app)
```bash
flutter pub get
cd apps/rider_app/ios && pod install && cd -
open apps/rider_app/ios/Runner.xcworkspace   # set Signing Team once (physical device)
flutter run -d "iPhone 15"                   # Simulator: no signing needed
```
- iOS deployment target is already 13.0 (flutter_stripe needs it).
- If `pod install` fails on the Stripe frameworks, add `use_frameworks!` +
  `use_modular_headers!` inside `target 'Runner'` in the generated `ios/Podfile`,
  then re-run `pod install`.

## Test flows to drive
- **Rider:** signup (login OTP is **6 digits**) → set name/email → pick
  destination → choose tier → add card (mock sheet until Stripe keys) → book →
  live-track → complete → tip → 5★ → receipt.
- **Driver:** signup → name → vehicle onboarding (auto-verified in dev) → go
  online → accept offer → "Arrived" → **start OTP is 4 digits** → complete →
  rate rider. Payouts screen shows a Connect "set up direct deposit" banner.
- **Safety:** the SOS sheet shows **"Call 911"** (display-only — never place a
  real call while testing).

## Gotchas carried over from Linux
- Login OTP = **6 digits**; trip-start OTP = **4 digits** (don't confuse them).
- Package ids: `in.novarobotics.ubernav.rider_app` / `.driver_app`.
- Backend e2e `app.close()` teardown hangs on a *persistent* dev stack but is
  fine on fresh services — not an app bug.
