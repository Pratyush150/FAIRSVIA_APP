# UberNav Codebase Audit — Mistakes & Improvements

**Method:** three parallel read-only agents (backend correctness/security · Flutter client · architecture/tests/CI), each citing `file:line`. **Date:** 2026-08-17.

> Honesty note: these are agent-reported findings from static reading, not all runtime-verified. The **Critical money/assignment items must be reproduced with a test before fixing** — don't change payment/dispatch code on a read-alone claim. Locations are given so each is checkable.

Severity: 🔴 Critical · 🟠 High · 🟡 Medium · ⚪ Low.

---

## 🔴 Critical — money & double-assignment (fix first, with a repro test)

| # | Finding | Location | Why it matters | Fix |
|---|---|---|---|---|
| C1 | **Capture can exceed the authorized hold** → capture rejected, driver never credited | `payments.service.ts:48` authorizes `fareEstimate`, `:112-157` captures `fareFinal`; `stripe-payment.provider.ts:62` | When the driven fare exceeds the estimate (the exact case odometer-recompute exists for), Stripe rejects the capture, `captureForTrip` throws before `ledger.record('earning')` → silent payout loss | Cap `amount_to_capture` at the authorized amount, or authorize a buffered hold; record the ledger earning in the **same transaction** as the capture-status update |
| C2 | **Driver withdrawal / payout over-withdrawal race (TOCTOU)** | `ledger.service.ts:82-90`, `payments.service.ts:463-497` | Balance read + debit are non-atomic; two concurrent withdrawals both pass the guard → driver overdraws, and the payout path issues **two real bank transfers** | Balance check + debit inside one `$transaction` with row lock / serializable, or a Redis lock keyed on `driverId`; record the debit before/with the transfer |
| C3 | **Double-assignment when `OFFER_TTL_MS` ≥ the hard-coded 20 s offer lock** | `dispatch.service.ts:26, 257, 286` | Offer lock is fixed `PX 20000` but `OFFER_TTL_MS` is env-configurable (demos use 90 s here); lock expires while the offer is live → same driver offered two trips, both can accept | Derive lock TTL from `OFFER_TTL_MS + buffer`; guard `assign()` on `driverActiveTrip` before committing |

**Note:** this repo's `.env` sets `OFFER_TTL_MS=90000` — so **C3 is live in the current config**, not hypothetical.

---

## 🟠 High

| # | Finding | Location | Fix |
|---|---|---|---|
| H1 | **Refund race over-refunds** a payment (read-modify-write, no txn) | `payments.service.ts:258-299` | Optimistic `updateMany` guard on prior `refundedAmount` inside a txn; call provider only after winning the claim |
| H2 | **Per-user promo limit bypassable** under concurrency (TOCTOU; only global limit is atomic) | `promo.service.ts:47-104`, `schema.prisma:447-458` | Add `@@unique([promoId, userId])`, handle P2002 |
| H3 | **Webhook "idempotency" claims before processing** → a transient failure permanently drops the event; also missing `charge.refunded`/`dispute`/`canceled` handlers | `payments.service.ts:504-560` | Claim + process in one txn (rollback claim on failure), or mark `processed` only after the handler succeeds |
| H4 | **Rating average lost-update race** (unlocked read-modify-write of `ratingAvg`/`ratingCount`) | `ratings.service.ts:64-83` | Raw `UPDATE … SET rating_count = rating_count+1 …` with row lock, or recompute from aggregate |
| H5 | **Stale JWT role; no revocation/ban check** — demoted/banned user keeps access until token expiry | `jwt.strategy.ts:27-29`, `roles.guard.ts:27-33` | Load user in `validate()`, reject if disabled; read role from DB (or token-version/`revokedAt`) for privileged routes |
| H6 | **Driver offer countdown auto-declines a ride the driver already accepted** (race) | driver `home_page.dart:702-711` + `driver_cubit.dart:155-160` | Stop the timer on accept; don't auto-decline while `state.busy` |
| H7 | **Accept button has no busy guard → double-accept** | driver `home_page.dart:857-862` | `onPressed: state.busy ? null : …`, show `loading: state.busy` |
| H8 | **`completeTrip` loses the completion if the earnings call fails** — driver stuck on `onTrip` | `driver_cubit.dart:194-220` | Move to `completed` as soon as `complete()` succeeds; load earnings best-effort separately |
| H9 | **Dispatch core loop effectively untested** (spec mocks everything, only tests enqueue/respond); no socket e2e of accept→OTP→meter→complete→capture | `dispatch.service.spec.ts:6-30`, `backend/test/app.e2e-spec.ts` | Unit-test `sweep`/`offerTo` with fake Redis + real state machine on a test DB; add a socket e2e for the lifecycle + concurrent-offer lock |

---

## 🟡 Medium

| # | Finding | Location | Fix |
|---|---|---|---|
| M1 | Fire-and-forget `notifyTrip` can raise an **unhandled promise rejection** (process-terminating) | `notifications.service.ts:73-88` + `void` call sites in `trips`/`dispatch`/`scheduled` | Make `notify()` swallow+log its own queue errors, or `.catch()` every `void` call |
| M2 | **Tip charge is non-idempotent** (fresh idempotency key each call) + read-modify-write | `payments.service.ts:301-337` | Stable idempotency key per trip+attempt; atomic `{ increment }`; gate on completed trip |
| M3 | **`captureForTrip` / cash-commission ledger writes not idempotent** — re-invoke double-credits the driver | `payments.service.ts:104-199` | Gate the ledger credit on payment not already captured; unique `tripId+type` |
| M4 | **Driver going offline mid-trip wipes active-trip Redis keys** (stops metering/streaming) | `drivers.service.ts:62-95` | Refuse offline (or preserve keys) when `driverActiveTrip` set |
| M5 | **`KEYS` scans on the hot Redis** (`admin.live`, `countOnlineDrivers`, `surge.snapshot`) + N+1 | `admin.service.ts:257,315`, `surge.service.ts:101` | Maintain an `online` SET; pipeline reads; never `KEYS` in handlers |
| M6 | **emit-after-close**: cubits `emit` after awaited work with no `isClosed` guard | rider `trip_cubit.dart` (112, 165, 196, 289), all driver cubit async | `if (isClosed) return;` before every post-await `emit` |
| M7 | **Socket connect failure unhandled**; state defaults `connected: true` → banner hidden | rider `home_page.dart:88-93`, driver `:73-78`, `realtime_client.dart:92` | Catch connect failure, surface retry, seed `connected: false` until first connect |
| M8 | **Location denial silently teleports rider to Miami** (permission dead-end, no "open settings") | `location_service.dart:30-50` | Surface a permission-denied UI state with an enable/settings action |
| M9 | **Non-`ApiException` (decode/TypeError) escapes `on ApiException` handlers** → infinite spinner (e.g. `ChatPage._load`) | `chat_page.dart:58-75` + cubits | Add a generic `catch (e)` fallback error state (as `AsyncContent` already does) |
| M10 | **Multi-step ride mutations not atomic** across DB+Redis+payments (complete/cancel) | `trips.service.ts:305-322, 463-506` | Wrap DB writes in `$transaction`; make Redis release idempotent + reconcile on retry |
| M11 | **Single Redis = matching SPOF** + 100 ms busy-poll holds a worker slot; `concurrency:100` ceiling | `dispatch.service.ts:335-349`, `dispatch.processor.ts:16`, `realtime.gateway.ts:65` | Replace poll with pub/sub or `BLPOP`; dedicate/replicate Redis for matching |
| M12 | **GPS ingest unpipelined** (~6 sequential Redis round-trips per ping) | `location.service.ts:59-101` | Pipeline/MULTI; cache `tier`/`riderId` on the socket at go-online |
| M13 | **Money as `Float`** in rate-card/competitor/sample tables (Trip/Payment use `Decimal`) | `schema.prisma:368-372, 388-397, 413-414` | `Decimal` for all currency config columns |
| M14 | **Sim-driving via module-level mutable globals in production widget tree** (never resets between trips) | `driver location_stream.dart:55-128` | Encapsulate in an injectable simulator gated on the mock flag; reset per trip |
| M15 | **`dispatch` reads `process.env` directly**, bypassing validated `ConfigService` | `dispatch.service.ts:26,39,46-47` | Surface tuning knobs through `AppConfig` with bounds |
| M16 | **God-widgets** with transport/state logic in the view layer (rider home 1.8k lines, admin home 1.9k) | rider/admin `home_page.dart`; `admin_api.dart` not shared | Push transport+state into cubits in `packages/core` |

---

## ⚪ Low

- **OTP start code (4-digit) has no brute-force lockout** — `trips.service.ts:260-263, 530`. Add per-trip attempt cap.
- **`incrWithTtl` can create a TTL-less key** (crash between `incr`/`expire`) — `redis.service.ts:43-49`. Use `SET … EX NX` + `INCR` or a Lua atomic.
- **No global HTTP rate limiting** (only per-phone OTP) — add `@nestjs/throttler`.
- **Unbounded/unpaginated queries** — driver earnings/history full scans (`drivers.service.ts:104-110`, `trips.service.ts:511-517`).
- **Confirm button rounds fare to whole dollars** while receipt uses cents — rider `home_page.dart:628-637`.
- **Hardcoded `$` ignores `Trip.currency`/`Fmt.money`** — many rider/driver sites.
- **Surge printed as a raw double** (`1.2000001x`) — rider `home_page.dart:488`.
- **`GeoPoint(0,0)` sentinel for unset pickup** — `destination_search_page.dart:68`.
- **`_onDriverLocation` mutates marker regardless of phase** — rider `trip_cubit.dart:95-100`.
- **Missing/marginal indexes** — `Trip.@@index([status])` doesn't cover `OR(riderId,driverId)+status IN(...)`; no scheduled-list index.

---

## Tests & CI

- **H9 (above)** — dispatch loop + socket ride lifecycle have no gating coverage; the only end-to-end driver path is the non-asserting `tools/fake-driver-simulator`.
- **No coverage floor, no `--fatal-infos`, no Android build gate** in `.github/workflows/ci.yml` (only web-build). Coverage can rot; Android can break unnoticed.
- **`admin_app` has zero tests** (highest-privilege surface: refunds, KYC, fare/surge/promo edits); **`safety/` (SOS) has no spec** — and SOS only WARN-logs + writes a `trip_event`, notifying no one (matches the GTM "never claim SOS" rule).
- **`npm audit --audit-level=high` as a hard gate** is non-deterministic (a new advisory fails unrelated PRs). Prefer scheduled or `critical`.
- **Doc drift:** README claims "44 unit / 19 e2e" (actual 26 spec files / ~50 e2e blocks); README's **Google Maps setup instructions don't match the OSM-based app**; `schema.prisma`/README claim **PostGIS in use** but it's entirely unused (plain-float lat/lng + Redis GEO).

---

## Cross-app duplication to consolidate (into `packages/core`)
- `<lat>,<lng>` location/mock parser — 3 copies (`rider location_service.dart:13-28`, `driver location_stream.dart:12-22`, `driver home_page.dart:46-55`).
- 12-hour AM/PM date formatting — 3 copies (`format.dart:11-17`, rider `home_page.dart:639-649`, `chat_page.dart:217-219`).
- `$X` money helper — 3 copies (rider `home_page.dart:1801`, `price_comparison_card.dart:13`, `Fmt.money`). One currency-aware formatter fixes the Low money-format items too.

---

## Verified sound (do NOT "fix" these)
- Trip state machine: optimistic `updateMany WHERE status=from` in a txn — correct concurrency guard.
- Stripe webhook signature: `timingSafeEqual` + timestamp tolerance over raw bytes — correct.
- Production config guard refuses placeholder JWT/DB/mock-SMS in prod.
- OTP **verify** path: sha256-hashed, attempt-capped, burned on success; `devEcho` gated to non-prod.
- Dispatch ghost-eviction pipelines its reads; odometer step is an atomic Lua `EVAL`.
- `AuthInterceptor` single-flight refresh; `copyWith` null-clear sentinels; `AsyncContent` shared loader — all sound.
- No circular NestJS modules; CI auto-globs new specs/tests.

---

## Suggested fix order
1. **C1, C2, C3** (money loss + double-assignment) — each with a repro test first.
2. **H1–H3** (refund/promo/webhook money-integrity), then **H6–H8** (driver accept/complete UX races — user-visible fare loss).
3. **H9** (dispatch + socket lifecycle tests) — this is what would have *caught* C1–C3.
4. **M1, M6, M7, M8** (crash/stuck-UI robustness), then the SPOF/pipeline items (M11, M12) before a second market.
5. Low items + duplication cleanup opportunistically.
