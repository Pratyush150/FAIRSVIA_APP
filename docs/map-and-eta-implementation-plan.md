# Map & ETA — Complete Implementation Plan

**Owner:** engineering · **Status:** in progress · **Last updated:** 2026-08-17

This is the single source of truth for finishing the map/ETA work discussed. It is
sequenced so every step is independently shippable, compiles, and never leaves the
working app broken. Progress is tracked with `[x]` / `[ ]` per step.

## Guiding rules (from CLAUDE.md)
- Absolute honesty: no step is "done" until its test passes; show failing output.
- Don't break working things: each step is additive + back-compatible; the OSM map
  keeps working throughout.
- Validate end-to-end: `flutter analyze` + tests, backend jest/e2e, and an emulator
  smoke test with a screenshot before a track is called complete.

## The key architectural fact
- Client map = `flutter_map` + OSM/MapTiler raster tiles (`packages/design_system/
  lib/src/widgets/app_map.dart`). NOT Google.
- Backend geo = `GeoProvider` chosen at boot: Google (if `GOOGLE_MAPS_API_KEY`) >
  OSRM+Nominatim > Stub (`backend/src/geo/geo.module.ts`). Currently OSRM (key empty),
  pointed at the Bhukum/Pune extract.
- **None of the "felt like Uber" gaps require Google.** They are client polish on the
  existing OSM map + backend ETA plumbing. Google is a separate, optional track.

---

## TRACK A — Gap-fixes on the existing OSM map (no Google needed, zero external cost)

Do this track first. It delivers the visible "feels like Uber" wins with no provider
change and no risk.

- [x] **A0. Backend driver→pickup ETA on assign.** `dispatch.service.ts`: widen
  `approachPolyline`→`approachRoute` (returns `RouteResult`), emit `etaSec` +
  `etaDistanceM` on `trip:accepted` (rider) and `trip:assigned` (driver). Reuses the
  route call already made — no extra provider traffic. **DONE** (typecheck clean, 160
  backend tests pass).
- [x] **A1a. Client model parses ETA.** `packages/shared_models/lib/src/
  assigned_driver.dart`: add `etaSec`/`etaDistanceM` + `etaLabel` getter
  ("Arriving in N min"). **DONE** (analyze clean).
- [ ] **A1b. Show ETA in the rider driver-sheet.** `apps/rider_app/lib/home_page.dart`
  `_DriverInfoSheet` (~line 1238): when not arrived and `assignedDriver.etaLabel != null`,
  show it in place of "On the way"; else fall back to "On the way".
  - Test: `shared_models` unit test for `fromAcceptedEvent` ETA parsing + `etaLabel`
    rounding; `flutter analyze`.
  - Done when: analyze clean + test passes.
- [ ] **A2. Offer card: rider identity + approach distance.**
  - Backend `dispatch.service.ts` `offerTo`: fetch rider (`fullName`, `ratingAvg`) once
    per dispatch (thread from `runDispatch`→`sweep`→`offerTo` to avoid a DB hit per
    offer); read driver loc from Redis; compute `haversineMeters` (already in
    `geo/geo.util.ts`) driver→pickup. Add to `trip:offer`: `rider:{name,rating}`,
    `approachDistanceM`.
  - Model `packages/shared_models/lib/src/ride_offer.dart`: add `riderName`,
    `riderRating`, `approachDistanceM` (nullable, back-compatible).
  - Driver UI `apps/driver_app/lib/home_page.dart` offer overlay (~682-855): show rider
    name + rating + "~X km to pickup".
  - Tests: backend `dispatch.service.spec.ts` asserts offer payload carries the fields;
    `shared_models` parse test; `flutter analyze`.
- [ ] **A3. ETA-based ranking of the nearest candidates.**
  - `dispatch.service.ts` `sweep`: after `nearestDrivers` (crow-flies), take the nearest
    N (≈5) and re-order by real road ETA via `geo.route(driverLoc→pickup)` (bounded
    calls; skip if provider is Stub or on error → keep crow-flies order). Favourites
    still jump the queue first.
  - Guard: never let ranking add unbounded routing calls; cap at N and fail-open.
  - Tests: unit test that, given mocked routes, a nearer-by-road driver is offered before
    a nearer-by-crow-flies one.
- [ ] **A4. Driver puck interpolation + bearing.** `packages/design_system/lib/src/
  widgets/app_map.dart`: animate the driver marker between GPS updates
  (Tween/`lerp` over ~1s) and rotate it to its heading. Requires threading a `heading`
  onto `AppMapMarker` (nullable) and the driver-location events carrying heading (rider
  side: `trip_cubit` `_onDriverLocation`; backend already ingests heading in
  `location.service`). Respect `prefers-reduced-motion` (no animation → snap).
  - Tests: widget test that the puck widget accepts heading + a golden if practical.
- [ ] **A5. Recenter / "my location" button (rider).** `apps/rider_app/lib/home_page.dart`:
  a FAB over the map that calls `AppMap.recenter` to the rider's current location
  (`AppMap` already supports `recenter`). Wire `LocationService.currentOrFallback()`.
  - Test: widget test that tapping the button triggers a recenter callback.
- [ ] **A6. Sheet-aware camera padding.** `app_map.dart`: accept a `bottomPadding` (or
  `EdgeInsets`) and use it in `CameraFit.bounds(padding: …)` so markers aren't hidden
  behind the bottom sheet. Rider home passes the sheet height.
  - Test: analyze + manual/emulator verification.

**Track A acceptance:** `flutter analyze` clean; all new/existing Flutter tests pass;
backend jest green; emulator smoke test shows live ETA + smooth puck + recenter, with a
before/after screenshot.

---

## TRACK B — Safe backend Google enablement (optional, gated on your console setup)

Makes geocoding/routing/ETA global + accurate, WITHOUT the client migration. Safe because
of the fallback wrapper.

- [ ] **B1. `FallbackGeoProvider`.** New `backend/src/geo/fallback-geo.provider.ts`
  implementing `GeoProvider`, composing a primary (Google) + secondary (OSM); each method
  tries primary, falls back to secondary on throw, logs the fallback. Wire in
  `geo.module.ts`: if Google key AND OSRM/Nominatim set → `FallbackGeoProvider(google, osm)`;
  else current precedence.
  - Tests: `fallback-geo.provider.spec.ts` — primary success passes through; primary throw
    → secondary used; both throw → error.
- [ ] **B2. Flip the key — ONLY after you confirm:** billing enabled + Maps/Places/
  Directions/Geocoding APIs enabled + key restricted (Android SHA-1 already provided).
  Set `GOOGLE_MAPS_API_KEY` in `backend/.env` (gitignored), `docker restart ubernav_backend`,
  then verify with one live `/places/autocomplete` + `/places/reverse` call. If anything
  fails, the fallback keeps OSM serving — no outage.
  - **Blocked on: user confirmation of console setup.** Do not flip before B1 + confirmation.

**Track B acceptance:** live autocomplete/reverse return Google results; forcing a Google
error still returns OSM results (fallback proven); backend jest/e2e green.

---

## TRACK C — Client Google Maps migration ("look exactly like Uber") — GATED DECISION

This is a large, higher-risk, ongoing-cost track. It does NOT fix the felt gaps (A1–A6
do). It only changes the *basemap look*. Recommendation: do Tracks A+B first; decide C
afterwards. Included here for completeness.

Tradeoffs to accept before starting C: Google Maps billing per map load; iOS cannot be
built/verified on this Linux box (code-ready only); your GTM strategy deliberately chose
OSM. If you still want the Google look, MapTiler with a custom style is a lower-cost way to
get an Uber-like map on the existing `flutter_map` — consider it as C-alt.

- [ ] **C1. Deps.** Add `google_maps_flutter` (+ `_web`) to `design_system`, `rider_app`,
  `driver_app`.
- [ ] **C2. Rewrite `AppMap`** onto `GoogleMap`, keeping its public API in `latlong2.LatLng`
  (convert internally) so the 3 call sites don't change. Map markers→`Set<Marker>`
  (BitmapDescriptor for the puck), route→`Set<Polyline>`, camera→`animateCamera`,
  `onCenterChanged`→`onCameraMove/Idle`, `onMapReady`→`onMapCreated`. Apply an Uber-like
  style JSON.
- [ ] **C3. Native key injection (gitignored).** Android: `secrets.properties` →
  Gradle `manifestPlaceholders["MAPS_API_KEY"]` → `AndroidManifest.xml`
  `com.google.android.geo.API_KEY`; `minSdk ≥ 21`. iOS: `AppDelegate.swift`
  `GMSServices.provideAPIKey` (code-ready only). Web: `index.html` Maps JS script.
- [ ] **C4. Validate** on the `pixel_uber` (google_apis) emulator — real tiles render;
  screenshot. iOS committed but unverified (state that honestly).
- [ ] **C-alt (cheaper).** Instead of C1–C4: set `--dart-define=MAPTILER_KEY=…` +
  a styled `MAPTILER_STYLE` in the existing `flutter_map` — Uber-like look, no Google
  billing, no native changes. One-line change.

**Track C acceptance:** map renders Google/MapTiler tiles on the emulator with a screenshot;
no regression in markers/route/camera; iOS config committed (unverified).

---

## Global validation gate (run before declaring the whole thing done)
1. `docker exec ubernav_backend npm test` (jest) — green.
2. `docker exec ubernav_backend npm run test:e2e` — green.
3. `flutter analyze` — clean.
4. `flutter test` across `rider_app`, `driver_app`, `packages/*` — green.
5. Emulator: boot `pixel_uber`, run a rider+driver match end-to-end, confirm live ETA +
   smooth puck + recenter + (if C done) Google tiles. Capture before/after screenshots.

## Execution order
A1b → A2 → A3 → A5 → A6 → A4 (puck is the fiddliest, do last in A) → B1 → (B2 on your
confirm) → decide C vs C-alt. Commit after each step with a clear message; keep CI green.

## Rollback
Every step is additive/nullable. Backend ETA fields default undefined; model fields default
null; the Google key flip (B2) is guarded by the fallback provider. Reverting any single
commit restores the prior working state with no schema/data changes.
