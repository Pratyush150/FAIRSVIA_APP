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
| **Open:** access tokens expire after 15 min but the socket re-sends the token captured at connect; a socket drop after that is rejected until relaunch (seen on the Android driver). Fix = token provider on every reconnect. | `realtime_client.dart` + both cubits — pending |

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
| Golden test no longer hardcodes Linux paths; pixel goldens skip off-Linux | `apps/rider_app/test/price_comparison_golden_test.dart` |

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

## 7. Still required before a field test
- Google Maps API key (iOS + Android) — map tiles are blank without it.
- Backend service keys (Google/OSRM routing, SMS, Stripe) and a phone-reachable backend URL.
- Signed device builds (Apple Team on the Runner targets); real GPS / background location only exercised with `MOCK_LOCATION`.
- Realtime token refresh on reconnect (section 2, open item).
