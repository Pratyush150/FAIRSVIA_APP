# Change log — Mac/iOS validation pass (2026-09-10 → 09-11)

Branch: `feat/map-eta-and-audit-fixes`. 22 commits on top of `eb709cf`
(120 files, +6 243 / −402). Everything below was verified on iPhone 17 +
iPhone 16 Pro simulators (iOS 26.5, Xcode 26.6, Flutter 3.44.6) against a
Mac-local backend, and the rider + driver apps were also run on an Android 15
emulator (`pixel_uber`). Automated gate at the end: `flutter analyze` clean,
Flutter tests 56 core / 21 design_system / 16 shared_models / 20 rider /
17 driver, backend jest 33 suites / 269 tests, `tsc` clean.

## 1. iOS build & project (first-ever iOS compile of this branch)
| What | Where |
|---|---|
| CocoaPods wiring committed (Pods refs, workspace entry, Pods-Runner xcconfig includes, lockfiles) | `apps/rider_app/ios/{Podfile.lock,Runner.xcodeproj/project.pbxproj,Runner.xcworkspace/contents.xcworkspacedata,Flutter/Debug.xcconfig,Flutter/Release.xcconfig}`, same under `apps/driver_app/ios/`, `apps/rider_app/ios/**/swiftpm/Package.resolved` |
| Home-screen labels "FairsVia Rider" / "FairsVia Driver" (were "Rider App"/"Driver App") | `apps/rider_app/ios/Runner/Info.plist`, `apps/driver_app/ios/Runner/Info.plist` (`CFBundleDisplayName`) |
| main merged into the branch (trip restore on cold start, reconnect on resume, identity-leak fix, vehicle-dialog double-show fix) | merge commit `616c021` |
| Setup doc rewritten: Google Maps key required, iOS 15 floor, simulator-runtime download, idb notes | `docs/ios-mac-setup.md` |
| Gitignored key files (NOT committed): `MAPS_API_KEY=…` | `apps/*/ios/Flutter/Secrets.xcconfig`, `apps/rider_app/android/secrets.properties`, `apps/driver_app/android/secrets.properties` |

## 2. Realtime / networking (root causes of "deaf" sessions)
| What | Where |
|---|---|
| Fresh socket per `connect()` (`enableForceNew`): the library reused one cached socket carrying the first-ever token, so re-login / token rotation / server restart left sessions deaf | `packages/core/lib/src/realtime/realtime_client.dart` |
| Serialised overlapping connects; explicit retry for `io server disconnect` and namespace `connect_error` (1 s→8 s backoff); `connected` edges derived correctly | same file; tests `packages/core/test/realtime_client_test.dart` (loopback socket.io server) |
| Subscribe to all events before the first `connect()` in both cubits | `apps/rider_app/lib/features/trip/trip_cubit.dart`, `apps/driver_app/lib/features/driver/driver_cubit.dart` |
| Chat reloads history on reconnect (deduped) | `packages/core/lib/src/chat/chat_page.dart` |
| Failed token refresh routes to sign-in instead of 401-looping on Home | `packages/core/lib/src/network/{auth_interceptor.dart,dio_client.dart}`, `packages/core/lib/src/auth/bloc/{auth_bloc.dart,auth_event.dart}`, `packages/core/lib/src/di/injector.dart` |
| Socket handshake fetches a fresh access token on every (re)connect (`connectWith` + `AuthInterceptor.freshAccessToken`, refreshes when the JWT is within 60 s of `exp`). Before: tokens expire after 15 min and the reconnect re-sent the stale one → rejected until relaunch (seen live on the Android driver). | `packages/core/lib/src/realtime/realtime_client.dart`, `packages/core/lib/src/network/{auth_interceptor.dart,dio_client.dart}`, both cubits + home pages; tests `packages/core/test/{realtime_client_test.dart,auth_interceptor_test.dart}` |

## 3. Rider app
| What | Where |
|---|---|
| Ride sheet: header under the Dynamic Island, phantom gap above tiers, Confirm off-screen → capped sheet height, stripped inherited inset, pinned Confirm footer | `packages/design_system/lib/src/widgets/app_sheet.dart`, `apps/rider_app/lib/home_page.dart` (`_RideConfirmFooter`), tests `packages/design_system/test/app_sheet_test.dart` |
| Cancel dialog closes itself when the trip ends underneath it; confirming no longer wipes the chosen destination | `apps/rider_app/lib/home_page.dart` (`_confirmCancel`), `trip_cubit.dart` (`isCancellable`, `cancelTrip`) |
| Recenter button works when GPS hasn't moved (`recenterSeq`) | `packages/design_system/lib/src/widgets/app_map.dart`, `apps/rider_app/lib/home_page.dart` |
| Cold-start restore repopulates pickup/dropoff/addresses/stops; no fabricated 5.0 rating | `apps/rider_app/lib/features/trip/trip_cubit.dart` (`_applyTrip`), `home_page.dart` |
| Saved-place quick-picks refresh after the account pages | `apps/rider_app/lib/home_page.dart` |
| Scheduled rides: 6-minute clamp in the picker and at send time (backend 5-min lead rule) | `apps/rider_app/lib/home_page.dart`, `trip_cubit.dart` (`_sendableSchedule`) |
| Reconnecting banner stacked above the top map buttons | `apps/rider_app/lib/home_page.dart` |

## 4. Driver app
| What | Where |
|---|---|
| Accept can't hang: safety timer after Accept; trip-scoped `offer_expired` | `apps/driver_app/lib/features/driver/driver_cubit.dart` |
| Approach camera fits once per leg (was every GPS tick, max-zoom at pickup) | `apps/driver_app/lib/home_page.dart` (`_fitBounds`) |
| Location permission gate before going online (+ Settings shortcut) | `apps/driver_app/lib/features/driver/{location_stream.dart,driver_cubit.dart,driver_state.dart}`, `home_page.dart` |
| Chat header shows the rider's name (`DriverState.riderName`) | `driver_cubit.dart`, `driver_state.dart`, `home_page.dart` |
| Stale route line cleared after a trip; sim car no longer restarts on unrelated errors | `apps/driver_app/lib/home_page.dart` (`_route`, `_simKey`) |
| Exact cash/earnings amounts (was rounded to whole dollars); vehicle dialog spacing | `apps/driver_app/lib/home_page.dart` |
| Reconnecting banner stacked above the status pill / menu | `apps/driver_app/lib/home_page.dart` |
| Driver-specific name-setup copy | `apps/driver_app/lib/app.dart`, `packages/core/lib/src/auth/presentation/name_setup_page.dart`, `packages/core/lib/src/router/app_router.dart` |
| Offer card units in miles/feet | `packages/shared_models/lib/src/ride_offer.dart` |

## 5. Shared packages
| What | Where |
|---|---|
| Driver puck 36 pt (was 108 pt); dark "night" basemap + de-cluttered light style | `packages/design_system/lib/src/widgets/{app_map.dart,map_styles.dart}` |
| Trip history hides the uncharged estimate on cancelled trips | `packages/core/lib/src/account/trip_history_page.dart` |
| Saved places: mounted guards, Home/Work chips enable Save | `packages/core/lib/src/account/saved_places_page.dart` |
| Scheduled rides: confirm dialog + in-flight guard | `packages/core/lib/src/account/scheduled_rides_page.dart` |
| Payouts: 2-decimal prefill, cent-precision validation, inline errors | `packages/core/lib/src/account/driver_payouts_page.dart` |
| Support: submitting flag reset in `finally` | `packages/core/lib/src/account/support_page.dart` |
| Profile edit refreshes the cached user | `packages/core/lib/src/account/account_menu_page.dart` |
| Receipt nets refunds, shows "Paid in cash" | `packages/core/lib/src/account/receipt_page.dart`, `packages/core/lib/src/trip/payments_remote_data_source.dart` |
| `Fmt.money` negatives as `-$1.30`; exported from `core` | `packages/core/lib/src/account/format.dart`, `packages/core/lib/core.dart` |
| Dead OSM tile-error filter removed | `packages/core/lib/src/debug/error_overlay.dart` |

## 6. Backend
| What | Where |
|---|---|
| `trip:offer_expired` when an accept lands late or assign fails | `backend/src/dispatch/dispatch.service.ts` |
| Prod boot guard: Stripe keys required, `DRIVER_AUTO_VERIFY` must be off | `backend/src/common/config/configuration.ts` |
| Durable capture retry job; no bogus payout split on failure | `backend/src/payments/{payments.processor.ts,payments.queue.ts,payments.service.ts,payments.module.ts}`, `backend/src/trips/trips.service.ts` |
| One tip per trip; cash never hits the card provider; refund recorded before Stripe with idempotency key | `backend/src/payments/payments.service.ts`, `stripe-payment.provider.ts`, migration `backend/prisma/migrations/20260910163809_payment_refunds_and_trip_payment_method/` |
| Start-code attempt lockout + timing-safe compare; active-trip dedupe (409); `POST /trips/:id/driver-cancel`; fare clamp 0.8×–1.5× estimate; 2-min cancel-fee grace; `paymentMethodId` honoured | `backend/src/trips/{trips.service.ts,trips.controller.ts,dto/driver-cancel-trip.dto.ts}`, `backend/src/pricing/pricing.service.ts` |
| GPS segment plausibility gate | `backend/src/location/location.service.ts` |
| Promo redemption released on cancel; count+insert in one txn | `backend/src/promo/promo.service.ts` |
| Rate limiting (`@nestjs/throttler`), trust proxy in prod | `backend/src/common/throttle/**`, `backend/src/app.module.ts`, `backend/src/main.ts`, `backend/package.json` |
| Refresh-token reuse detection, `isActive` checks, `POST /auth/logout` | `backend/src/auth/{auth.service.ts,auth.controller.ts,dto/logout.dto.ts}` |
| Socket auth checks active user; gateway CORS allow-list; disconnect on deactivate | `backend/src/realtime/{realtime.gateway.ts,realtime.service.ts,gateway-cors.ts}` |
| Chat gated to live trips, TTL set once, per-user token bucket | `backend/src/chat/chat.service.ts` |
| Push: allSettled delivery, prune dead tokens, no token hijack; `ParseUUIDPipe` on inbox ids | `backend/src/notifications/**` |

## 7. 2026-09-14 audit round (API + UI + Uber/Android gap analysis)
Full findings and status: `docs/ios-audit-report-2026-09-14.md`.

| What | Where |
|---|---|
| Live ETA/distance on every driver ping (`trip:driver_location` carries `etaSec/remainingM/phase/accuracy/ts`); rider "Arriving 12:47 PM · 1 min · 164 ft to go"; stale-ping watchdog | `backend/src/location/location.service.ts`, `apps/rider_app/lib/features/trip/trip_cubit.dart`, `apps/rider_app/lib/home_page.dart` |
| Price lock: `POST /trips` takes `quotedFare/quotedSurge`, 409 `PRICE_CHANGED` → rider re-confirms with the new price | `backend/src/trips/trips.service.ts`, `apps/rider_app/lib/features/trip/trip_cubit.dart`, `packages/shared_models/lib/src/trip_estimate.dart` |
| Arrival geofence 150 m; fare `breakdown` on completion + receipt; `GET /trips/active` restores driver/vehicle/ETA | `backend/src/trips/trips.service.ts`, `packages/shared_models/lib/src/fare_breakdown.dart`, `packages/core/lib/src/account/receipt_page.dart` |
| Presence sync: `driver:status_changed`, `forceOffline` syncs DB + Redis; WS exception filter with real messages | `backend/src/realtime/{realtime.gateway.ts,ws-exceptions.filter.ts}`, `backend/src/drivers/drivers.service.ts`, `apps/driver_app/lib/features/driver/driver_cubit.dart` |
| Offer carries road `approachEtaS/approachDistanceM`, `surge`, `dropoff`, `durationS`; declined set stops re-offers; `offer_expired` only on failed assign | `backend/src/dispatch/dispatch.service.ts`, `packages/shared_models/lib/src/ride_offer.dart`, `apps/driver_app/lib/home_page.dart` (`OfferOverlay`) |
| Surge demand counted once per rider (SET) | `backend/src/surge/surge.service.ts` |
| Places autocomplete biased to the rider, `distanceM` per result, sorted by distance | `backend/src/places/**`, `backend/src/geo/google-geo.provider.ts`, `packages/shared_models` places |
| `ParseUUIDPipe` on trips/receipt/support/favorites ids; favorites existence check; saved-place label required; driver-facing notification copy | `backend/src/{trips,payments,support,favorites}/*.controller.ts`, `favorites.service.ts`, `users/dto/create-place.dto.ts`, `notifications/notifications.service.ts` |
| Precise-location handling (temporary full accuracy, `PreciseRide` purpose key), location banner, driver online gate; ping `accuracy`/`ts`; `bestForNavigation`; mock location ignored in release | `apps/rider_app/lib/features/trip/{location_service.dart,location_banner.dart}`, `apps/driver_app/lib/features/driver/location_stream.dart`, `apps/*/ios/Runner/Info.plist` |
| Map: `MapCameraMode.followDriver` (heading-up, zoom 17, tilt 30, pan suspends, north-up street zoom restored on exit), `MapMarkerKind` (blue "me" dot, z-order), route trimming helpers | `packages/design_system/lib/src/widgets/{app_map.dart,map_geo.dart}` |
| Driver Navigate hand-off (Google Maps → Waze → Apple Maps → web), live "N m to pickup/dropoff" | `packages/core/lib/src/util/navigation_launcher.dart`, `apps/driver_app/lib/home_page.dart`, driver `Info.plist` (`LSApplicationQueriesSchemes`) |
| Ride-options sheet at 58 % with pinned confirm footer; promo error visible; cancel is server-confirmed; recenter re-fits the phase; chat unread badges; start-code inline error + reset; floating snackbars above sheets | `packages/design_system/lib/src/widgets/app_sheet.dart`, `apps/rider_app/lib/home_page.dart`, `apps/driver_app/lib/home_page.dart` |
| Rider handles `trip:cancelled`, `trip:otp_locked`, `trip:payment_warning`; driver earnings loaded at startup | `apps/rider_app/lib/features/trip/trip_cubit.dart`, `apps/driver_app/lib/features/driver/driver_cubit.dart` |
| Branding: FairsVia icons + launch images (iOS + Android), `CFBundleName`, portrait-only, unique URL schemes `fairsvia-rider` / `fairsvia-driver` | `apps/*/ios/Runner/{Info.plist,Assets.xcassets}`, `apps/*/android/app/src/main/res/mipmap-*` |
| Short realistic ride recorder (~106 m trip, 55 m approach, steps fire on real server state) | `tools/ios-e2e-record-short.sh` |
| Debug error banner no longer masks real errors (plain text + copy) | `packages/core/lib/src/debug/error_overlay.dart` |

## 8. 2026-09-14 functional round (three UI-driven test passes on the final builds)
Findings and status: `docs/ios-audit-report-2026-09-14.md` §8.

| What | Where |
|---|---|
| Rider cold relaunch mid-ride: `GET /trips/:id` and `/trips/active` carry `driver` + `vehicle` | `backend/src/trips/trips.service.ts` (`driverSnapshot`) |
| Scheduled rides: `trip:accepted` carries `startOtp`; rider fetches the trip when the event arrives without one | `backend/src/dispatch/dispatch.service.ts`, `apps/rider_app/lib/features/trip/trip_cubit.dart` (`_onAccepted`) |
| Cancellation fee capped at the fare estimate, waived while the start code is locked, amount on every trip payload and in the cancel dialog; "Ride cancelled." feedback | `backend/src/trips/trips.service.ts`, `packages/shared_models/lib/src/trip.dart` (`cancellationFee`), `apps/rider_app/lib/home_page.dart` |
| Driver payout computed on the gross fare (promo absorbed by the platform) | `backend/src/payments/payments.service.ts` (`splitFor`) |
| Receipt: minimum-fare top-up line, card brand/last4 | `backend/src/trips/trips.service.ts` (`breakdownFor`), `backend/src/payments/payments.service.ts` (`getReceipt`), `packages/shared_models/lib/src/fare_breakdown.dart`, `packages/core/lib/src/account/receipt_page.dart`, `packages/core/lib/src/trip/payments_remote_data_source.dart` |
| Tier "N min away" = nearest online driver of the tier (null → "no cars nearby") | `backend/src/dispatch/dispatch.service.ts` (`nearestDriverEtaS`), `packages/shared_models/lib/src/fare_tier.dart`, rider `home_page.dart` |
| Price lock bounces only on a fare change (not a surge-only tick) | `backend/src/trips/trips.service.ts` (`assertPriceLock`) |
| Tip reaches the driver's completion sheet (`trip:tip_added`) | `backend/src/payments/payments.service.ts`, `apps/driver_app/lib/features/driver/driver_cubit.dart` (`_onTipAdded`) |
| Driver presence: app polls `GET /drivers/me` every 30 s while online; the endpoint reports the live Redis status | `apps/driver_app/lib/features/driver/driver_cubit.dart` (`_pollPresence`), `backend/src/drivers/drivers.service.ts` (`getProfileWithPresence`) |
| Driver: distance to pickup/dropoff along the road; street-level zoom on recenter; vehicle editor (menu → Vehicle) with validation; onboarding waits for the server | `apps/driver_app/lib/home_page.dart`, `packages/core/lib/src/driver/driver_remote_data_source.dart` (`DriverProfile`, `me()`) |
| Saved cards: remove / set default (`DELETE /payments/methods/:id`, `PATCH .../:id/default`), "Add card" chip, cash default with no card | `backend/src/payments/{payments.controller.ts,payments.service.ts}`, `packages/core/lib/src/account/payment_methods_page.dart`, rider `trip_cubit.dart` |
| Sign-in: Continue pinned above the keyboard, country code required (`+`), strict E.164 on the server; OTP error inline with cleared digits; dev-code chip tappable | `packages/core/lib/src/auth/presentation/{phone_entry_page.dart,otp_page.dart}`, `backend/src/auth/dto/*.ts` |
| Sign out: confirmation, `POST /auth/logout`, driver goes offline first, blocked mid-trip | `packages/core/lib/src/auth/auth_repository.dart`, `packages/core/lib/src/account/account_menu_page.dart` |
| Support sheet errors inline; driver copy; category "Other" | `packages/core/lib/src/account/support_page.dart` |
| Scheduling uses the iOS wheel picker; promo error scrolls into view; Home/Work shortcuts on Plan your ride; duplicate autocomplete/reverse calls removed | rider `home_page.dart`, `destination_search_page.dart`, `map_picker_page.dart` |
| Dev request log lines show method, URL and status | `backend/src/common/logging/logging.module.ts` |
| Vehicle fields must be non-empty (trimmed) | `backend/src/drivers/dto/onboarding.dto.ts` |

## 9. Still required before a field test
- Google Maps key is in place locally (gitignored files) — every new machine needs it added again.
- Backend service keys (Google/OSRM routing, SMS, Stripe) and a phone-reachable backend URL.
- Signed device builds (Apple Team on the Runner targets); real GPS / background location only exercised with `MOCK_LOCATION`.
