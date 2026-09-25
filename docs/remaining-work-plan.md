# Remaining Work Plan

> **New session picking this up?** Read
> [session-handoff.md](session-handoff.md) first — environment traps, what is
> verified vs assumed, and corrections to this repo's own documentation.

The single authoritative list of what is left. **Rewritten 2026-09-23** after
the owner's decisions below and a fresh audit that checked older documents
(`architecture-explained.md`, `codebase-audit.md`, both 2026-09-10) against the
live code instead of trusting them. **Updated 2026-09-25**: the pilot market is
**Pune, India (INR)** — the 2026-09-23 "Uzbekistan first" plan below is
superseded for the pilot — and Plan F "Map Glass" is the final look. The full
product audit of 2026-09-25 ([plans/audit-2026-09-25.md](plans/audit-2026-09-25.md))
carries the current scores, 34 observed inconsistencies and a top-10 fix list.

---

## Current state — 2026-09-25

| | |
|---|---|
| **Market** | **Pilot in Pune, India**: rupees (₹, whole-rupee fares, Indian digit grouping), km, +91 phone numbers, `Asia/Kolkata`, India emergency numbers (112 / Police 100 / Ambulance 108). Server: `MARKET_CURRENCY=INR BUSINESS_TZ=Asia/Kolkata`; apps: `--dart-define=MARKET=in`. Uzbekistan (`uz`, UZS, +998) remains a *later* market on the same switches — not current work |
| **Look** | **Plan F "Map Glass" is final** (owner, 2026-09-25): the default build (no `THEME` flag) for rider and driver. The other looks (turquoise, A–E, G) stay in code behind `--dart-define=THEME=…` but do not ship |
| **Apps** | rider + driver **v2.2.0 (build 6200)** on Android (emulator-verified). **iOS last built 2026-09-14 — unverified since** |
| **Overall audit score** | 5.5 / 10 ([audit](plans/audit-2026-09-25.md)): core ride loop works end to end; money correctness (0 m completion charged the full estimate), unmasked calls, no i18n, visible polish bugs and all of iOS hold it back |

## Done 2026-09-23 → 2026-09-25 (this week)

| Area | What landed |
|---|---|
| Market | One market setting (`MARKET` / `MARKET_CURRENCY` / `BUSINESS_TZ`): ₹, km, +91 local-number input stored as E.164, Pune fares, ₹50 cancellation fee, rupee tips; US price comparison off outside the US; place names landmark-first instead of Plus Codes |
| Rides | Auto-rickshaw and Bike taxi for Pune end to end (held back by default, switchable by the owner) |
| UI (ui-10 plan) | Phase 1 audit bugs (Miami map, marker overlap, dead ride types); one icon family (Phosphor); plate-first driver card, four-box PIN, labelled Safety pill; login with +91 chip, Terms/Privacy links, OTP autofill; choose-ride / finding / in-trip / completed screens; radar at the pickup; type scale, tokens, motion, accessibility pass (3.1–3.4, 4.1–4.3) |
| Look | Several looks built side by side (A Midnight, B Daylight, C Day & Night, D Local, E Ink & Paper, F Map Glass, G 3D Clay); **F chosen as final**; Light / Dark / Same-as-phone applies instantly, even mid-ride |
| 2.1.0 / 2.2.0 | New rider Home, smooth locating, native Share + Call, chat redesign, Lottie moments; driver offerable right after a trip; rate card with the driver's name |
| Analytics | Grafana "Today" page + five focused pages (§0c); ghost-driver count fixed |
| Safety / store | SOS that reaches people, in-app account deletion, payout and capture races fixed (tables below) |
| Size | Release APK build that leaves out art/fonts of looks that don't ship, and per-ABI APKs (`tools/apk/release_apk.py`, `make apk-rider` / `make apk-driver`) |

---

## Owner decisions — 2026-09-23

| Decision | Effect on this plan |
|---|---|
| ~~Launch market is Central Asia — Uzbekistan first — not Florida~~ **Superseded for the pilot:** the pilot runs in **Pune, India (INR)**; Uzbekistan is a later market | Florida-specific items (F.S. 627.748 insurance) stay dropped. §3 now tracks Pune/India; the Uzbekistan items are kept at the end of §3 as later work |
| **Business APIs that need the company's GST registration and company mobile number are deferred** until those exist | SMS sender, and any vendor account needing company KYC, stay mocked. **Do not spend time on them now** — polish what we own instead |
| **Referral program stays on the roadmap** | Kept in §7, Tier 3. Not started |
| **Grafana is the analytics + monitoring + alerting surface** — no separate reporting dashboard in the admin app for now | Checklist gap analysis in §5 |
| **Post-booking / driver-arriving screen brief** to be built for Android and iOS | Gap analysis in §6 |
| TLS, error tracking, Postgres backups, a privacy policy: **do them ourselves, now** | Done — see below |

---

## Done 2026-09-23 (verified, not assumed)

| Item | What exists | How it was verified |
|---|---|---|
| **Error tracking — backend** | `@sentry/nestjs`: `src/instrument.ts` (first import in `main.ts`), `SentryModule` + `SentryGlobalFilter`. Off until `SENTRY_DSN` is set — same mock/real pattern as every provider | tsc clean; 436 unit + 48 e2e green; dev backend restarted and healthy; a real exception was delivered as a Sentry envelope to a local fake endpoint |
| **Error tracking — all three Flutter apps** | `sentry_flutter` 9.x in `packages/core`, wired into the shared `runGuarded`/`reportError`, so rider, driver and admin all report through one path. Off until built with `--dart-define=SENTRY_DSN=...` | 2 new tests (error forwarded; socket noise filtered); analyzer clean in all 6 packages; rider + driver debug APKs build. `sentry_flutter` 8.x **broke the Android build** (Kotlin 1.6 language level) — found by building, fixed by moving to 9.x |
| **Postgres backups** | `infra/backup/`: nightly verified `pg_dump`, 7 daily / 4 weekly / 6 monthly rotation, hourly retry on failure, `pg_backup` service in the prod stack, `make backup-db` / `make restore-db`, `PgBackupStale` alert via node_exporter | **Restore drill:** identical row counts in all 24 tables (230,381 rows). Alert loaded, inactive on a fresh backup, went pending when the timestamp was aged 2 days |
| **TLS / HTTPS automation** | `infra/tls/`: nginx on 443 (TLS 1.2/1.3, HSTS), HTTP → HTTPS redirect, certbot issue + 12-hourly renewal, self-signed placeholder so the stack always boots | Drill on the real compose definitions: HTTPS 200 over HTTP/2, redirect, ACME path, **server refuses TLS 1.1**, each security header exactly once, `/metrics` blocked, renewal hand-off served a new cert with no restart. Also fixed a latent bug: single-file bind mount meant nginx config edits were silently ignored on reload |
| **Privacy policy** | `docs/legal/privacy-policy.md` — **draft**, written from the actual data model | Each claim checked against the code. One draft claim was false ("phone numbers are never shown") and was corrected — book-for-someone-else shows the passenger's phone to the driver |

## Done 2026-09-23, second pass (verified on Android; iOS pending a Mac)

| Item | What changed | How it was verified |
|---|---|---|
| **Payout double-pay race (real money)** | Stripe payouts now reserve the balance first (serializable), key the bank transfer on the reservation, give it back only on a definite rejection, and hold it for reconciliation if the outcome is unknown | Real-Postgres test: 6 simultaneous payouts of 60 against a 100 balance — **old code sent 6 transfers, new code 1** |
| **Capture / cash / tip / cancellation fee atomic (C1)** | Payment state and the driver's ledger entry commit in one transaction with a status guard | Concurrency tests (6× at once → booked once); removing the guard makes them fail |
| **Promo race (H2)** | Was already fixed (serializable transaction) — the plan was wrong. Found a real bug under it: serialization conflicts in raw SQL surfaced as a 500, not "no discount". One helper now handles both forms | Concurrency test |
| **In-app account deletion (store blocker §2.1)** | `DELETE /users/me` + shared delete page for rider and driver. Refused during a ride or with a driver balance | 3 e2e + 6 widget tests; on the emulator a throwaway rider was deleted and a driver with a balance was refused |
| **SOS that reaches people** | Emergency contacts (up to 3) texted with location, car and plate; local numbers from config (Police 102 / Ambulance 103 / Fire 101); `SafetyIncident` lifecycle; `SosRaised` critical alert; admin **Safety tab** with badge + banner on every tab; the false "Safety team alerted. Stay on the line." copy removed | 3 e2e, 11 widget, 4 admin tests; alert went *firing* 10 s after a real SOS; full SOS on the emulator during a live ride; admin acknowledge audited |
| **Backend still said "FairsVia"** | Login-code SMS, receipt email, passenger SMS, comparison label → one `BRAND_NAME` constant | Unit tests |

## Found while testing — fixed or tracked

| Finding | Status |
|---|---|
| **e2e SOS tests left open alerts in the dev database**: 15 open incidents from test phones showed in the admin console's SOS banner and would fire `SosRaised` in dev monitoring | Fixed: the suite deletes its incident in `afterAll`; the 15 test incidents were closed with a note. After a full e2e run, 0 open |
| **Ending a ride early after adding a stop can still charge most of the stop fare**: a ride ended 256 m in was charged $26.46, because of the 0.8× floor on the quote, and that quote included a stop the car never reached | Tracked, needs a decision: should the floor apply only when the whole quoted route was driven? |
| **Production queues would never connect**: BullMQ dropped the Redis password, and the prod Redis requires one — dispatch, payments and notifications would all fail | Fixed + proven against a password-protected Redis (old options time out, new ones process the job). Uncommitted at time of writing |
| e2e workers consumed the dev server's live jobs (shared Redis), slowing teardown past 60 s | Fix ready (`QUEUE_PREFIX=e2e` for tests); being verified |
| e2e teardown failed green suites (5 s hook limit) | Fixed (60 s) |
| DiskSpaceLow alert told on-call to `docker system prune` (would wipe the owner's robotics images) | Fixed |
| `tools/webserve.py` served nothing after any `flutter build web` (cwd was the deleted build dir) | Fixed |
| `tools/visual-check/shot-monitoring.mjs` still hard-codes the old LAN IP and a removed tab | New `shot-safety*.mjs` resolve the IP; the old script to be removed |
| Dev watch-mode backend kept serving old code after a change (no restart after recompile) | Trap — restart the container before live checks. Added to handoff |
| Emulator ANR in the location plugin (`geolocator` registers NMEA on the main thread; the emulator GPS HAL stalled) | Emulator HAL issue, not app code — **watch for it on real phones** (field test) |
| **Driver card row overflowed off-screen with long car names/plates** (33 px; 125 px at large text) | Being fixed as part of the arriving-screen redesign (§6); regression test written |
| Driver app `versionCode` is 1 in `pubspec.yaml` while a 4001 build exists | Must increase monotonically before any store upload |
| Already built, plan was stale: resend-OTP countdown, name + email at sign-up, add-stop at booking | Removed from §7 |

## Needs the owner

- **Pushing**: auto mode blocks a token inside a command. Once per machine, cache it
  yourself (see the chat) and every verified change is then pushed right away.
- **"Add trip" in the arriving-screen brief** — add a stop to this ride, or book
  another ride? "Pre-book" is being built either way.

---

## 0. Uber-parity UI (owner request 2026-09-23) — superseded by the ui-10 plan

The live UI roadmap is [plans/ui-10-audit-plan.md](plans/ui-10-audit-plan.md);
the look is Plan F "Map Glass" (final). The table below is kept as history.

Goal: using RideVela next to Uber, the apps should look and feel the same —
colours, type, spacing, buttons, sheets, map, ride list, flows — on Android
and iOS (one Flutter codebase, so both change together).

**Boundary (legal):** Uber's own brand assets are not copied — its logo,
the licensed "Uber Move" font, its car illustrations and icon set. Copying
those is trade-dress infringement. We match the *style*: free equivalents of
the same visual weight (Inter for type, Material icons, our own car glyphs),
and the name stays RideVela.

| Phase | What | State |
|---|---|---|
| 1 | Design tokens: monochrome palette (white / black / Uber-style greys, black primary actions, blue links), Inter type scale, 8 px radii, 56 px black buttons, light/dark map styles, black route line | ✅ ink follows light/dark; greyscale maps; black pickup ring + drop-off square; borderless cards; grey secondary buttons |
| 2 | Rider screens: home "Where to?" pill + "Later", search, ride options list (selected = outlined), arriving, in-trip, completed/rating | 🟡 home, search, ride list, route framing, arriving sheet done and seen on the emulator (light + dark); completed/rating and account pages next |
| — | **Brand palette: "Samarkand Turquoise"** (owner's choice 2026-09-23) — teal-navy / turquoise ink, turquoise route + selection, more legible map with turquoise water | Default v1.3.0 → 2.0; **superseded 2026-09-25 by Plan F "Map Glass"** as the shipped look. `THEME=turquoise` builds the previous default; `THEME=mono` the black-and-white variant |
| 3 | Driver screens: online/offline, offer card, en-route, trip, earnings | 🟡 new palette, font, buttons and map apply (seen on the Moto); layout polish of the offer card and trip sheet still to do |
| 4 | Shared: sign-in/OTP, account/menu, receipts; admin console palette | 🟡 new palette, font and buttons apply everywhere; layout polish still to do |
| 5 | Verify: goldens updated, analyzer + tests, screenshots of every screen light + dark on the emulator, APKs to the pilot phones; iPhone check added to `mac-ios-pilot-handoff.md` | ⏳ |

---

## 0c. Simpler analytics (owner request 2026-09-24) — ✅ done 2026-09-24

The single 72-panel Analytics page was too dense for someone new. Rebuild as
one plain-language **Today** home page + five focused pages, same data.

| Page | Answers | Panels |
|---|---|---|
| 🏠 Today (home) | rides done today · money in today · people using the app today · drivers online now · riders waiting now · anything broken now · rides per hour | 7 |
| 🚕 Rides | completed / cancelled / no driver found · success rate · average fare · average pickup wait · rides per hour/day · why rides are cancelled | ≤ 8 |
| 💰 Money | money in · money we kept · drivers earned · refunds · cash vs card · money per day · failed payments | ≤ 8 |
| 👥 People | all users · new sign-ups · people using the app (daily, 30 days) · growth (30 days) | ≤ 8 |
| 🧑‍✈️ Drivers | online / free / busy now · offers accepted · driver cancellations · top drivers · supply over time | ≤ 8 |
| 🖥️ Tech health | server load, speed, errors, database, alerts firing | ≤ 12 |

Rules: questions or plain phrases as titles; one-sentence ⓘ on every tile; ₹
units; one colour meaning everywhere (green good / orange watch / red act);
the same page buttons on every page; currency (INR) and time zone
(Asia/Kolkata) fixed and hidden. Nothing from the old page is dropped.

Built by `infra/monitoring/grafana/build_dashboards.py`; all 52 queries return
live data with 0 errors; checked rendered. Also fixed: "drivers online" counted
ghost drivers whose app had stopped sending positions (111 shown, 0 real) — it
now uses dispatch's freshness rule.

---

## 0b. Clean analytics data (owner: "when it's needed")

Grafana's pipelines are live (Prometheus scrape every 15 s, SQL on the live
DB, daily-activity tracking), but the dev database it reads holds ~8,000 test
users and ~15,500 test rides (load sweeps since 2026-07-28, e2e runs, pilot
testing). Before the numbers are shown as real:

| # | Step | Notes |
|---|---|---|
| 1 | e2e suites use their own database (`ubernav_test`) | Config only (`DATABASE_URL` in `test/setup-env.ts` + a `migrate deploy` on it). Stops every test run adding fake users/rides and inflating DAU |
| 2 | Archive and remove test/load-test data from the live DB | `make backup-db` first; remove by the test phone prefixes and the load-test date range; **owner go-ahead required** before any delete |
| 3 | Re-check the dashboard | DAU/MAU, completion rate and revenue should then reflect only pilot use |

---

## 1. Blocked on the owner only (not code)

| Priority | Item | Exactly what is needed |
|---|---|---|
| 🔴 | **Real TLS certificate** | A DNS **A record** for the API hostname (e.g. `api.ridevela.com`) → the production server's public IP, in the Cloudflare account, "DNS only". Then one command — `infra/tls/README.md`. Today neither `api.ridevela.com` nor `api.fairsvia.com` exists in DNS |
| 🔴 | **Production server location** | India's DPDP Act 2023 obligations (and any transfer restrictions the government notifies) — confirm with counsel. Decides where the DB, backups and off-site copies may live. (For Uzbekistan, later: its personal-data law is understood to require in-country storage — confirm then) |
| 🔴 | **Regulatory / licensing for ride-hailing in Pune / Maharashtra** (and each later market) | Aggregator licence under the Motor Vehicle Aggregator Guidelines and Maharashtra's rules, passenger insurance, driver requirements — confirm with counsel. No code can resolve this; it may add product requirements (licence documents, GST invoices) |
| 🔴 | **Background-check / KYC provider for India** | Checkr is US-only. Integration layer exists (mock by default); needs an Indian vendor or a manual document-review process |
| 🟠 | **Privacy policy completion** | Company legal name, address, contacts (pending registration), retention periods, counsel review under the DPDP Act, Hindi + Marathi translations, a public URL. The draft still names Uzbekistan as the first market — update it with counsel |
| 🟠 | **Masked calling provider** | Calls dial the other party's real number today. Options, flow, cost and the decisions needed: [plans/masked-calling.md](plans/masked-calling.md) |
| 🟠 | **UPI payment provider** | Payment is cash or a Stripe card only; no UPI. The payment layer is provider-abstracted, so this is a new provider, not a rewrite |
| ⏸ | **Deferred by decision:** SMS sender, Stripe webhook secret, push keys, any company-KYC vendor | Waiting on GST registration + company mobile number |
| 🟡 | Alertmanager delivery | 10 min once a Slack webhook or email is chosen |
| 🟡 | Android launcher icon (old "F") | An icon asset |
| 🟡 | iOS rebuild + physical-iPhone run | A Mac (last built 2026-09-14) |
| 🟡 | Sentry project | Create one, set `SENTRY_DSN` — two minutes, then error tracking is live |
| 🟡 | Off-site backup destination | A bucket or second server, in-country if counsel says so |

---

## 2. App-store blockers we can build ourselves

| # | Item | Why |
|---|---|---|
| 2.1 | ✅ **Done 2026-09-23** — ~~In-app account deletion~~ — rider and driver | **Required by Apple (since 2022) and Google Play (since 2024)** for any app with sign-up. Verified 2026-09-23: no delete-account endpoint or screen exists. Needs: endpoint, anonymisation that keeps legally-required trip/payment records, confirmation UI, and a web deletion link for Play |
| 2.2 | **Privacy policy + terms links in the apps** | Both stores require them reachable in-app. Blocked only on the public URL |
| 2.3 | **ATS `NSAllowsArbitraryLoads` removal** (iOS) | Apple rejects it; TLS now exists to replace it. Needs a Mac to verify |

---

## 3. Launch-market work: Pune, India (pilot)

Re-checked 2026-09-25 (the 2026-09-23 version of this section planned for
Uzbekistan; that is now the "later" table below).

| # | Item | State |
|---|---|---|
| 3.1 | **Routing + geocoding map data** | ✅ The loaded OSRM/Nominatim data covers Maharashtra, which includes Pune; Pune rides and place search work end to end. Geocoder data quirks remain ("Unnammed Road", a result with no distance — audit #33) |
| 3.2 | **Currency** | ✅ INR end to end via `MARKET_CURRENCY=INR` + `MARKET=in` (whole-rupee rider fares, Indian digit grouping). Open: driver earnings show paise while rider amounts are whole rupees (audit #15); **M13** money as `Float` in fare config (§4); tax/GST-style receipt and invoice number |
| 3.3 | **Phone numbers** | ✅ +91 default, local-number input stored as E.164. Open: one display format everywhere (audit #13) |
| 3.4 | **Language** | ❌ No i18n at all (no ARB files, no `flutter_localizations`). Hindi + Marathi (+ Noto Sans Devanagari); start now, it gets costlier with every screen |
| 3.5 | **Time zone** | ✅ `BUSINESS_TZ=Asia/Kolkata` for day boundaries |
| 3.6 | **Payments** | ❌ UPI (see §1) |

**Later market — Uzbekistan** (not current work; same switches with `MARKET=uz`):
Geofabrik Uzbekistan extract into OSRM + Nominatim (check disk first), UZS
fare config (no minor unit in practice), +998 input, Uzbek (Latin) + Russian,
`Asia/Tashkent`, in-country data storage, a local payment processor (Payme /
Click — Stripe is, to our knowledge, not available to Uzbekistan-registered
merchants).

---

## 4. Money-path and safety correctness (from the 2026-09-10 audit, re-checked)

| ID | Issue | Status 2026-09-23 |
|---|---|---|
| C2 | Driver withdrawal double-spend race | ✅ **Fixed** — serializable transaction (`ledger.service.ts`) |
| H1 | Refund over-refund race | ✅ **Fixed** — reserve-then-call-provider, idempotency key, reversal on failure |
| C1 | Capture vs driver earning not atomic | ✅ **Fixed 2026-09-23** (was: partly fixed. Capture is capped at the authorised hold. The payment-status update and the ledger credit are still two statements (`payments.service.ts` ~257–267) — a crash between them leaves a captured fare with no driver credit. Put both in one transaction |
| H2 | Per-user promo limit bypass under concurrency | ✅ **Already fixed** (serializable txn; the earlier "open" was wrong). Raw-SQL conflict 500 fixed 2026-09-23 |
| M13 | Money stored as `Float` | 🟡 **Open** — `FareConfig` / competitor tables (`baseFare`, `bookingFee`, `minFare`, `observedFare`). Trip/Payment are correctly `Decimal`. Fix together with 3.2 |
| — | **SOS notifies no one** | ✅ **Fixed 2026-09-23** — contacts texted, ops alerted, admin Safety tab. Needs Alertmanager delivery wired before launch (§1). Was: Writes an alert for the admin view only — no SMS, call or emergency contact. Must not be labelled an emergency feature until it alerts someone (trusted contacts, ops on-call). India numbers now: 112 / Police 100 / Ambulance 108 (`EMERGENCY_NUMBERS`) |
| — | Driver document upload | Open — onboarding is typed text; verification is a manual admin toggle |

---

## 5. Grafana analytics checklist — gap analysis

Against the owner's "Grafana Dashboard — Core List". Grafana already has a
**Postgres datasource**, so most business panels are SQL over existing tables.

| Section | Already there | Missing → how |
|---|---|---|
| App overview | Rides completed (today), completed/cancelled by outcome + reason, completion rate, gross revenue (today, per hour) | Total users, new users (SQL on `users`) · total rides all-time · average fare (SQL) · **DAU / MAU** — needs a throttled `last_active_at` on users; trip counts would under-count riders who open the app and don't book |
| Live operations | Active trips, drivers online (+ by tier), dispatch backlog (= unassigned), match latency | Available vs busy split (online minus drivers on a trip) · **average pickup ETA** — actual accepted→arrived from `trip_events` · **driver acceptance / decline / expiry rate** — needs a new `dispatch_offers_total{outcome}` counter |
| Users & drivers | — | User growth, driver growth, active users/drivers, driver utilisation (time on trip ÷ time online), rides per driver — SQL, utilisation needs online-time tracking |
| Revenue & payments | Gross revenue, platform fee (= commission) | Net revenue (fee − refunds) · driver payouts (ledger) · payment success rate (SQL + `payment_failures_total`) · refunds (`payment_refunds`) |
| System health | CPU, RAM, disk, load, req/s, latency percentiles, 5xx rate, Postgres connections/transactions, Redis, event-loop lag, logs | **WebSocket connections** — new gauge · uptime panel (`process_start_time_seconds` already exported) · slow-query view |
| Alerts (12 rules) | Backend down, high error rate, disk low, match latency, dispatch backlog, active trips near ceiling, no drivers online, vendor errors, payment failures, Postgres connections, Redis memory, backup stale | **Database down** (`pg_up == 0`) · **high API latency** (p95 on HTTP, distinct from match latency) · **host CPU / memory overload** · ride anomalies (cancellation-rate spike) |

Effort: ~2 days. Three new backend metrics (offer outcomes, WebSocket gauge,
last-active), ~20 SQL panels, 4 alert rules. All alerts need Alertmanager
delivery (§1) before they reach a person.

---

## 6. Post-booking / driver-arriving screen — gap analysis (Android + iOS)

Against the owner's brief, checked in `rider_app/lib/features/trip/`:

| Brief item | State |
|---|---|
| Live map with safety button | ✅ Built (live car, SOS button) |
| Prominent "SAURAV is arriving now" banner | 🟠 Status copy exists but is generic ("Your driver is on the way / has arrived"). Needs the driver's name and banner styling |
| 4-digit ride PIN | ✅ Built — 4-digit start code shown to the rider only |
| Pickup spot + ride category + payment method | ❌ Not shown on this sheet |
| Driver photo, name, rating | 🟠 Name + rating yes; **photo no** (initials) — needs photo upload + storage (shared with §4 document upload) |
| Car image, registration number, model | 🟠 Plate + make/model yes; **car image no** |
| "I'm on my way" CTA (rider tells the driver they are coming) | ❌ Not built — needs a socket event + driver-app notice |
| Overflow menu (•••) for ride options | ❌ Not built — should hold cancel, share trip, contact support |
| Promotional content below ride details | ❌ Not built — needs a content source (admin-managed) |
| "Add trip" and "Pre-book" quick-action cards | ❌ Not built. Scheduled rides exist server-side, so Pre-book is mostly UI. "Add stop" mid-trip (§7 Tier 2) is a prerequisite for "Add trip" if it means adding a stop |

Being Flutter, one implementation serves both platforms; iOS still needs a Mac
build to verify. ~3–4 days, excluding photo storage.

---

## 7. Feature gaps (unchanged, value-ordered)

**Tier 1:** editable pickup · in-app masked calling ([plan](plans/masked-calling.md)) · driver + vehicle photos
· wait timer / no-show UI.
**Tier 2:** rebook a past trip · add stop / change destination **mid-trip**
(adding stops at booking already exists) · set-default / delete card.
(Resend-OTP countdown and name + email at sign-up already exist.)
**Tier 3:** UPI for India (moved up to §1/§3.6 — the pilot needs it); Payme /
Click later for Uzbekistan · settings screens (i18n moved to §3.4) ·
**referral program (kept by owner decision)** · pool rides and add-ons.

Also: 26 iOS backlog items (iOS audit) · 4 cosmetic backend issues (S6–S9).

---

## 8. Verification gaps

| # | Gap |
|---|---|
| 8.1 | Production profile never benchmarked — every capacity number is from the dev stack. Needs `infra/.env` |
| 8.2 | iOS never on a physical iPhone; not rebuilt since 2026-09-14 |
| 8.3 | ~43 stale trips stuck in `accepted`/`in_progress` in the dev DB from an old load-test run |
| 8.4 | The architecture docs say "Postgres + PostGIS", but **PostGIS is not installed in the running database** and no code uses it (geo is Redis GEO + OSRM). Harmless; the docs should stop claiming it |

---

## Kubernetes

Assessed and deliberately **not** planned: measured capacity ~25–50k
registered users on one box vs a 10k target. Revisit only after 8.1 gives real
production numbers. A possible in-country hosting requirement (§1) also favours a
simple single-server deployment at launch.

---

## Suggested order

| When | What |
|---|---|
| **Now (owner)** | DNS record for the API host · pick the production server · start licensing/insurance and background-check vendor conversations for Pune · choose a masked-calling provider ([plan](plans/masked-calling.md)) and a UPI provider · create a Sentry project |
| **Next (us)** | Audit top 10 ([audit §C](plans/audit-2026-09-25.md)): dark OTP number, Lottie dash, complete-trip guard (0 m at full fare), radar anchor, warning contrast, formatters · §6 arriving screen leftovers |
| **Then** | §3.4 i18n (Hindi + Marathi) · M13 · masked calling · §5 Grafana panels · §8.1 benchmark |
| **Ongoing** | §7 by tier |
| **Needs a Mac** | §2.3, §8.2 |

## Companion documents

| Document | Covers |
|---|---|
| [external-connectors.md](external-connectors.md) | Third-party integrations and how to switch each on |
| [monitoring-and-actions-plan.md](monitoring-and-actions-plan.md) | Observability stack, ops actions, Kubernetes assessment |
| [frontend-maintainability-plan.md](frontend-maintainability-plan.md) | God files, model contract, admin_app tests |
| [field-testing-plan.md](field-testing-plan.md) | On-road verification (23 cases) |
| [plans/audit-2026-09-25.md](plans/audit-2026-09-25.md) | Full product audit: scores, 34 inconsistencies, top-10 fixes |
| [plans/masked-calling.md](plans/masked-calling.md) | Masked calling: why, providers in India, flow, cost, owner decisions |
| [legal/privacy-policy.md](legal/privacy-policy.md) | Privacy policy draft |
| `infra/tls/README.md`, `infra/backup/README.md` | TLS and backup runbooks |
