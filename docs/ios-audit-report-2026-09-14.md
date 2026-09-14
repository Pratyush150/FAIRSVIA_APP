# FairsVia iOS audit report — 2026-09-14

Branch `feat/map-eta-and-audit-fixes`. Everything below was run on this Mac
(Xcode 26.6, iOS 26.5 simulator runtime, Flutter 3.44.6, CocoaPods 1.17.0)
against the local backend (`npm run start:dev`, Postgres 16 + Redis via
Homebrew, Google geo provider with a real Maps key in gitignored files).
Simulators: rider on iPhone 17, driver on iPhone 16 Pro. Nothing in this
report was run on a physical iPhone (see §7).

Three read-and-drive audits were run first, then the findings were fixed,
then the final builds were re-verified on both simulators and recorded.

| Audit | Method | Findings |
|---|---|---|
| A. Backend API | every controller/DTO/service read, then 148 REST calls + a scripted rider/driver trip with full socket capture (~120 more calls) | 5 bugs, 9 design points, everything else OK |
| B. iOS UI feature matrix | 167 screenshots across 3 rides (cash+chat, card+tip, rider cancel), dark mode, XXL text, background/resume, sign-out | 17 ranked defects + polish list |
| C. Uber iOS / Android parity | every map, location, trip and realtime file plus both Info.plists and asset catalogs, compared with Uber iOS behaviour and the Android build | 26 backlog items (6 P0, 14 P1, 6 P2) + 11 iOS must-dos |

Status legend: **Fixed** = changed on this branch and re-checked on the
simulators; **Partial** = part of the item done; **Open** = not done, with
the reason.

## 1. Backend API audit (A)

88 app-facing routes and socket events were exercised. Verified OK without
changes: OTP request/verify/burn, refresh rotation + reuse detection, logout,
per-IP throttle (exactly 5 then 429), every DTO validation shape, users/places
CRUD + ownership, favorites, inbox/unread/read-all, device register (409 on
another account's token), support tickets + threads, Google autocomplete /
details / reverse, estimate (single + stops) + comparison, promo
quote/redeem/release, mock card add/list/sync, receipts (cash + card), tip once
then 409, ratings both ways with running averages, history, earnings, ledger,
Connect onboard/status/payout (mock), the full trip socket lifecycle
(`trip:matching → offer → accepted → arrived → started → driver_location ×N →
completed`), OTP lockout (5 wrong → 15 min, rider gets `trip:otp_locked`),
driver-cancel, no-drivers after the 45 s window, scheduled trips (BullMQ job),
socket auth rejection, health and metrics.

Timing observed: offer reached the driver 344 ms after `POST /trips` returned;
`trip:accepted` reached the rider 318 ms after the accept; a driver location
ping reached the rider in 2 ms.

| # | Sev | Finding | Status | Where |
|---|---|---|---|---|
| 1 | Medium | Any `HttpException` inside a socket handler reached the client as `Internal server error`, so a driver never saw "Finish your current trip before going offline" | Fixed: WS exception filter emits `exception {code, message, event}`; driver app shows the message | `backend/src/realtime/ws-exceptions.filter.ts`, `apps/driver_app/lib/features/driver/driver_cubit.dart` (`_onServerException`) |
| 2 | Low | Non-UUID path ids returned 500 on trips, receipt, support and favorites routes | Fixed: `ParseUUIDPipe` on every id param | `backend/src/{trips,payments,support,favorites}/*.controller.ts` |
| 3 | Low | Favoriting a non-existent driver id returned 200 and a phantom row | Fixed: existence check → 404 | `backend/src/favorites/favorites.service.ts` |
| 4 | Low | Saved place accepted an empty label | Fixed: `@IsNotEmpty` | `backend/src/users/dto/create-place.dto.ts` |
| 5 | Low | DB driver status stayed `online` after a socket drop (Redis went offline) | Fixed: `forceOffline` syncs DB + Redis and emits `driver:status_changed` | `backend/src/drivers/drivers.service.ts`, `backend/src/realtime/realtime.gateway.ts` |
| S1 | Design | Surge escalated from one rider's own retries (1.2× → 2.0× in 30 s; cancelled trips never decremented demand) | Fixed: demand is a per-cell SET of rider ids, so retries count once | `backend/src/surge/surge.service.ts` |
| S2 | Design | Declining driver was re-offered the same trip every ~2.5 s | Fixed: per-trip declined set (10 min TTL) | `backend/src/dispatch/dispatch.service.ts` |
| S3 | Design | Duplicate accept after assignment sent a stray `trip:offer_expired` | Changed: `offer_expired` is sent only when the assign actually fails | `backend/src/dispatch/dispatch.service.ts` |
| S4 | Design | Driver inbox got the rider's copy ("Rate your driver") | Fixed: driver-facing copy per milestone | `backend/src/notifications/notifications.service.ts` |
| S5 | Design | Rider's quote was not locked; the server could charge a different surge than the sheet showed | Fixed: `POST /trips` takes `quotedFare/quotedSurge`, returns 409 `PRICE_CHANGED`, rider re-confirms with the new price | `backend/src/trips/trips.service.ts`, `apps/rider_app/lib/features/trip/trip_cubit.dart` (`_applyPriceChange`) |
| S6 | Design | `/places/details` with a bad placeId → 502 rather than 400 | Open (cosmetic) | `backend/src/places/places.controller.ts` |
| S7 | Design | Multi-stop estimate polyline is straight segments between legs | Open (per-leg Google routing is used for distance/time; the drawn line is not road geometry) | `backend/src/trips/trips.service.ts` |
| S8 | Design | 429 body lacks the `error` field other errors carry | Open (cosmetic) | `backend/src/common/throttle/**` |
| S9 | Design | Bad promo at create is silently dropped (quote endpoint is the check) | Open (by design; the app always quotes first) | `backend/src/promo/promo.service.ts` |

## 2. iOS UI audit (B)

| # | Defect (as observed on the Sep 12 build) | Status | Where |
|---|---|---|---|
| 1 | Rider charged 2.0× surge on a 1.0× quote, no re-confirm | Fixed (price lock, see S5) | rider `trip_cubit.dart`, backend `trips.service.ts` |
| 2 | Driver UI said "Online" while the server had it offline; first request got `no_drivers` | Fixed: `driver:status_changed` flips the pill; presence re-synced on reconnect | `driver_cubit.dart` (`_onServerStatus`), `realtime.gateway.ts` |
| 3 | "Arrived" accepted 220 m away; rider told "Your driver is here" | Fixed: 150 m server geofence; driver sees the live distance | `trips.service.ts`, driver `home_page.dart` (`_distanceLabel`) |
| 4 | "Arriving in N min" never updated | Fixed: server-routed `etaSec/remainingM` on every ping; rider shows "Arriving 12:47 PM · 1 min · 164 ft to go" | `backend/src/location/location.service.ts`, rider `trip_cubit.dart` (`liveEtaSec`), `home_page.dart` (`_liveEtaLabel`, `_tripEtaLine`) |
| 5 | Driver camera never followed the car; no Navigate | Fixed: heading-up follow camera (zoom 17, tilt 30, user pan suspends), Navigate → Google Maps / Waze / Apple Maps; north-up street zoom restored when the leg ends | `packages/design_system/lib/src/widgets/app_map.dart` (`MapCameraMode`), `packages/core/lib/src/util/navigation_launcher.dart` |
| 6 | Car invisible to the rider on a short approach | Fixed: bounds always include the car, padded above the sheet; verified in the final video | rider `home_page.dart` |
| 7 | Ride-options sheet hid payment/schedule/promo behind a nested-scroll trap; promo error under the pinned footer | Fixed: sheet at 58 % with a pinned footer, errors above it | `app_sheet.dart` (`footer`, `maxHeightFraction`), rider `home_page.dart` (`_RideConfirmFooter`) |
| 8 | No blue "my location" dot; city-level home zoom | Fixed: blue dot marker, initial zoom 16 | `app_map.dart` (`MapMarkerKind.me`), rider `home_page.dart` |
| 9 | Recenter inert during a trip | Fixed: recenter re-fits the current phase | rider `home_page.dart` (`_refitCurrentBounds`) |
| 10 | No unread badge for chat on the driver map | Fixed on both apps (`unreadMessages`, badge icon) | rider/driver `home_page.dart`, cubits |
| 11 | Search not biased to the rider; no distance per row | Fixed: lat/lng bias + `distanceM`, sorted by distance | `backend/src/places/**`, `google-geo.provider.ts`, `shared_models` places |
| 12 | Driver got the rider's completion copy | Fixed (S4) | `notifications.service.ts` |
| 13 | Cancel fee copy vague; no confirmation after cancel; no driver compensation info | Partial: cancel is now server-confirmed and the sheet stays on failure; the fee amount is still not shown up front | rider `home_page.dart` (`CancelRideDialog`), `trip_cubit.dart` (`cancelTrip`) |
| 14 | Completion/receipt had no fare breakdown | Fixed: `breakdown` on completion and receipt, "Fare details" expander | `trips.service.ts`, `shared_models/fare_breakdown.dart`, `receipt_page.dart`, rider `home_page.dart` (`_FareDetails`) |
| 15 | "$7" in the tier list vs "$6.85" in the footer; "No drivers" rows priced in history | Partial: history hides the estimate on non-charged trips; tier list rounding unchanged | `trip_history_page.dart` |
| 16 | "Earned today" on the offline sheet disagreed with "Today's earnings" | Fixed: earnings loaded at startup; final video shows $31.38 before and $37.88 after a $6.50 fare | `driver_cubit.dart` |
| 17 | Wrong start code: snackbar covered the CTA, digits not cleared | Fixed: inline error, boxes reset, floating snackbars moved above the sheet | driver `home_page.dart` (`_StartTripSheet`), `otp_input.dart` |

Polish items from the UI audit still open: Cupertino date picker for
scheduling (Material picker is used), chat quick replies, wait timer after
arrival, pin-lift animation on the map picker, sign-out confirmation, profile
save toast, photo upload. Dropoff pin now snaps to the route end (was in the
water).

## 3. Uber iOS / Android parity backlog (C)

| # | Pri | Item | Status |
|---|---|---|---|
| 1 | P0 | Precise Location never checked | Fixed: reduced accuracy detected, temporary full accuracy requested (`PreciseRide` key in both Info.plists); driver refuses to go online on reduced accuracy; rider gets a banner |
| 2 | P0 | Rider silently fell back to Miami when location was denied/off | Fixed: `LocationResult {source, issue}`, persistent banner with Settings deep-link; the fallback is never used as the pickup |
| 3 | P0 | No push / background delivery for the rider | **Open**: needs Firebase `GoogleService-Info.plist`, APNs key and the `aps-environment` entitlement from the project owner. Backend token endpoint exists; the client registration is not wired |
| 4 | P0 | ATS `NSAllowsArbitraryLoads`, localhost default base URL | **Open** for release: both Info.plists still allow arbitrary loads; device builds must pass `--dart-define=API_BASE_URL` |
| 5 | P0 | Location pings had no accuracy, so noisy fixes were metered | Fixed: `accuracy` + `ts` on every ping, server gate, `bestForNavigation` on trip |
| 6 | P0 | Cancel reset the UI even when the server call failed | Fixed: success-only reset |
| 7 | P1 | One-shot approach ETA | Fixed (live, server-routed) |
| 8 | P1 | No on-trip ETA / remaining route / follow camera | Fixed: remaining polyline trimmed behind the car, arrival time line, follow camera on the driver |
| 9 | P1 | Recenter dead during a trip | Fixed |
| 10 | P1 | Stale driver pings never surfaced | Fixed: 20 s watchdog → "Waiting for your driver's location…" |
| 11 | P1 | Offer card lacked road ETA, dropoff, duration, surge | Fixed: road `approachEtaS/approachDistanceM`, dropoff, "X min · Y mi", surge badge |
| 12 | P1 | No navigation hand-off | Fixed (Google Maps → Waze → Apple Maps → web) |
| 13 | P1 | Arrived not geofenced; no wait timer / no-show | Partial: 150 m geofence and driver-cancel with reason exist on the backend; no wait timer or no-show UI on either app |
| 14 | P1 | Cold-start restore lost the driver card | Fixed: `GET /trips/active` and `trip:sync` carry driver, vehicle, ETA |
| 15 | P1 | Rider ignored `trip:cancelled` / `otp_locked` / `payment_warning` | Fixed: all three handled |
| 16 | P1 | Masked call, share-trip live link, pickup notes | **Open** (driver phone is now in `AssignedDriver`; no call button, share still copies text) |
| 17 | P1 | Stock pins, no z-order, generic puck | Partial: z-order fixed (car above pins), 36 pt puck, blue rider dot; pins are still stock Google hues |
| 18 | P1 | Rider position was a single fix at launch | Partial: "you are here" dot and pickup refresh; no continuous stream while idle |
| 19 | P1 | Driver camera did not follow while driving | Fixed |
| 20 | P1 | Marker interpolation rebuilds the whole marker set each frame | Unchanged; needs on-device profiling |
| 21 | P2 | Finding-driver stage has no progress | Open |
| 22 | P2 | Receipt lacks breakdown / map | Partial: breakdown done; no map thumbnail |
| 23 | P2 | `MOCK_LOCATION` / `SIM_SPEED_MPS` honoured in release | Fixed: ignored under `kReleaseMode` |
| 24 | P2 | Driver accuracy tier | Fixed (`bestForNavigation`, 5 m filter) |
| 25 | P2 | No pre-permission explainer | Open |
| 26 | P2 | Rider arrival camera hit max zoom | Fixed |

iOS must-dos from the same audit: branded icons + launch images (done, both
platforms), portrait-only (done), unique URL schemes `fairsvia-rider` /
`fairsvia-driver` (done), `NSLocationTemporaryUsageDescriptionDictionary`
(done), `LSApplicationQueriesSchemes` for navigation (done),
`PrivacyInfo.xcprivacy` + `ITSAppUsesNonExemptEncryption` (**open**, needed
for TestFlight), background-location behaviour on a real device
(**unverified**, needs the phone).

## 4. Verification of the final builds

Gate run on the final code (all local):

| Suite | Result |
|---|---|
| `flutter analyze` (whole monorepo) | No issues |
| `packages/core` | 89 passed |
| `packages/design_system` | 28 passed |
| `packages/shared_models` | 35 passed |
| `apps/rider_app` | 70 passed, 1 skipped (golden, Linux-only) |
| `apps/driver_app` | 40 passed |
| backend `jest` | 335 passed |
| backend `tsc --noEmit` | OK |
| backend e2e | 4 pre-existing failures: the specs predate the one-live-ride guard and the chat gating and still expect the old behaviour |

On-device checks on the final simulator builds: precise-location banner and
gate, search ranked by distance, price-change re-confirm (forced by a surge
override), live "Arriving … ft to go" line counting down, follow camera with
heading, Navigate opening the maps chooser, arrival geofence (button refused
at 220 m, accepted inside 150 m), start-code inline error and lockout message,
chat badge on both apps, completion sheet with fare details and tip, driver
earnings consistent across sheets, dark mode on both apps.

Recording: `~/Desktop/FairsVia-iOS-final-ride-2026-09-14.mp4` (109 s at 1×,
rider left / driver right). Produced by `tools/ios-e2e-record-short.sh`:
~106 m trip on Biscayne Blvd, driver starts ~55 m away, simulated car at
4 m/s along the real route, every step fires on the real server state
(Redis position within 8 m, OTP read from the DB).

## 5. Android comparison

The Flutter code is shared, so every fix above applies to Android. The only
platform branches are the driver foreground service + wake lock (Android) and
the background location settings + precise-location request (iOS). The
Android build was not re-run on this Mac (no emulator here); it was last
validated on the Linux box per `docs/changelog-ios-validation-2026-09-10.md`.
Android still needs the same `secrets.properties` Maps key on any new machine.

## 6. Still required before a field test

1. Push notifications: Firebase project + `GoogleService-Info.plist` per app,
   APNs key, `aps-environment` entitlement, then wire `firebase_messaging` to
   `POST /notifications/devices`.
2. Release hygiene: remove `NSAllowsArbitraryLoads` (keep local networking in
   Debug only), add `PrivacyInfo.xcprivacy` and `ITSAppUsesNonExemptEncryption`.
3. A phone-reachable backend URL over HTTPS (for a LAN test,
   `http://192.168.1.44:3000/api/v1` works with the ATS exception still in place).
4. Real service keys on the backend (SMS, Stripe) if the test is not on the
   dev OTP.
5. Update the 4 stale backend e2e specs.

## 7. Physical iPhone status

The connected phone (iPhone 14, iOS 26.6.1, UDID
`29BC91C0-25E6-5370-87CE-AB96C5113504`) is now paired with this Mac, but the
device tunnel reports unavailable (phone locked or disconnected at the time of
checking), Xcode has no Apple ID signed in, and `security find-identity` finds
no code-signing identity. A device build therefore cannot be signed yet.
Needed from the owner: sign in to Xcode → Settings → Accounts with the Apple
ID (free account is enough for a 7-day development install), unlock the phone
and accept the Trust prompt. After that: set the team on both Runner targets,
build with `API_BASE_URL=http://192.168.1.44:3000/api/v1` and no
`MOCK_LOCATION`, install rider + driver, and run the driver bot near the
phone's real GPS.
