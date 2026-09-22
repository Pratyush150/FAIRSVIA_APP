# Remaining Work Plan

Everything outstanding, in execution order. Compiled 2026-09-18 from a live
audit of the running stack plus the existing `UBER_GAP_ANALYSIS.md` and
`ios-audit-report-2026-09-14.md`. **Updated 2026-09-22.**

## What is done since this was written

| | |
|---|---|
| Stage 1 — latent production bugs (1.1, 1.2, 1.3) | **Done.** Shutdown hooks armed; `/health` split into liveness/readiness with a real 503; `audit_log` + a global interceptor keyed on `@Roles(admin)`. |
| Observability (`monitoring-and-actions-plan.md` Phase 2) | **Done.** Prometheus + Grafana + Alertmanager + Loki in `infra/monitoring/`, three provisioned dashboards, 11 alert rules, business metrics in the registry. |
| Ops actions (Phase 3) | **Done.** Four audited kill switches with a console tab. |
| Live-map / ride-UI work | **Done and validated on Android** (7 end-to-end rides on the emulator). |

## What is actually left

Everything below is **external** — it needs an account, a key, a certificate or
a Mac, not more code:

| Priority | Item | Blocked on |
|---|---|---|
| 🔴 | **OTP SMS is mocked — nobody can really log in** | You. AWS creds already present; flip `SMS_PROVIDER` off `mock` |
| 🔴 | **TLS/HTTPS is off** | A certificate. nginx block is written and commented out. Unblocks the next two |
| 🔴 | **Stripe webhooks rejected** (`STRIPE_WEBHOOK_SECRET` absent) | You, after TLS |
| 🔴 | **Background checks mocked** — likely a legal requirement to carry paying passengers | External vendor. **Longest lead time of anything here** |
| 🟠 | **Push notifications mocked** | Mixed (FCM/APNs keys) |
| 🟠 | **iOS not rebuilt since 2026-09-14, never on a physical iPhone** | A Mac. See `handoff-for-mac.md` |
| 🟡 | **Alertmanager has no delivery wired** — deliberately, so it cannot look armed while pointing nowhere | 10 min: fill in Slack or SES |
| 🟡 | **Passenger-side tracking link** for "book for someone else" — the booker tracks fine, the passenger has no account and only gets SMS | ~1 day of code |
| 🟡 | **Android launcher icon still shows the old "F" mark** | An icon asset |
| 🟡 | **Disk at 98%** on the build box; `DiskSpaceLow` is firing for real | `docker system prune` (~40 GB reclaimable) |

Field verification is tracked separately in
[field-testing-plan.md](field-testing-plan.md) — 23 cases, 13 of which must be
run in a moving vehicle.

Storage/disk capacity is **owned by the project owner** and deliberately not
tracked here.

## Companion documents

| Document | Covers |
| --- | --- |
| [external-connectors.md](external-connectors.md) | All six third-party integrations and how to switch each on |
| [monitoring-and-actions-plan.md](monitoring-and-actions-plan.md) | Observability stack, ops actions, Kubernetes assessment |
| [frontend-maintainability-plan.md](frontend-maintainability-plan.md) | God files, model contract, admin_app tests |

This document sequences those three plus the work not covered by any of them.

---

## Stage 0 — Repo hygiene (do first, ~1 hour)

The branch `feat/map-eta-and-audit-fixes` is **107 commits ahead of `main`**
with uncommitted work on top.

1. Commit the load-test fixes — `ride-load.mjs` and `spike-load.mjs` carry real
   bug fixes (rider leak, arrival geofence) and `README.md` carries the
   corrected measured numbers. These are currently unsaved.
2. Commit the four planning documents.
3. **Merge to `main`.** 107 commits is a large unmerged surface; every extra day
   raises the cost of the eventual merge.

---

## Stage 1 — Latent production bugs (~0.5 day)

Three defects that are invisible today and bite under production conditions.
Detail in [monitoring-and-actions-plan.md](monitoring-and-actions-plan.md)
Phase 1.

| # | Defect | Consequence |
| --- | --- | --- |
| 1.1 | `app.enableShutdownHooks()` never called in `main.ts`, though Prisma, Redis and all four queue processors implement `onModuleDestroy` | SIGTERM is ignored; any restart or rolling deploy hard-kills in-flight dispatch jobs and WebSockets with no drain |
| 1.2 | `/health` returns HTTP **200** while reporting `status: "degraded"` | A backend with a dead database stays in the load balancer serving traffic. Needs liveness/readiness split with a real 503 |
| 1.3 | No audit log — 22 models, none recording admin actions | Refunds, surge changes, fare edits, driver verification and user deactivation are all unrecorded. Authorization is correct; accountability is missing |

**Do these before anything else technical.** 1.1 and 1.2 are prerequisites for
any orchestrator, and 1.3 must land before the dashboard grows action buttons.

---

## Stage 2 — Release blockers (~1 day of work + external lead time)

Cannot ship to either app store without these.

| # | Blocker | Owner | Notes |
| --- | --- | --- | --- |
| 2.1 | **TLS / HTTPS is off** | us | Backend serves plain HTTP. iOS ATS requires TLS 1.2+; Android blocks cleartext. The nginx config block is written and commented out — needs a certificate and uncommenting. Also unblocks Stripe webhooks |
| 2.2 | **ATS `NSAllowsArbitraryLoads`** still set in both `Info.plist`s | needs Mac | Apple rejects at review. Device builds must pass `--dart-define=API_BASE_URL` (iOS audit P0 #4) |
| 2.3 | **Push notifications don't work** | mixed | Mock provider on both platforms. See connectors doc §3 |
| 2.4 | **OTP SMS is not delivered** | us | `SMS_PROVIDER=mock`. Users cannot actually log in. Connectors doc §4 |
| 2.5 | **Background checks are mocked** | external | Likely a legal requirement to carry paying passengers. Longest lead time of anything here — **start the commercial process immediately**. Connectors doc §6 |
| 2.6 | **Stripe webhooks rejected** | us | `STRIPE_WEBHOOK_SECRET` absent, handler fails closed. Payments capture but never reach final state. Connectors doc §1 |

**Start 2.5 and the SES production-access request today** — both wait on other
organisations and everything else is faster than they are.

---

## Stage 3 — Connectors go-live

Fully specified in [external-connectors.md](external-connectors.md). Summary:
six vendors, two live, one half-wired, three mocked. Cheapest real win is
flipping `SMS_PROVIDER` and `EMAIL_PROVIDER` off `mock` — the AWS credentials
are already present.

Verify every change with `GET /api/v1/admin/diagnostics/probe`, which pings each
configured vendor read-only.

---

## Stage 4 — Close the verification gaps

| # | Gap | Blocked by |
| --- | --- | --- |
| 4.1 | **Production profile never benchmarked.** Every capacity number we hold was measured on the dev stack running `npm run start:dev` (TypeScript watch mode, single replica). Production uses a compiled build with two replicas, so real capacity is likely 2–4× higher and currently unknown | Needs `infra/.env` with two passwords (copy `infra/.env.example`) |
| 4.2 | ~~Nothing on iOS has ever been compiled or run.~~ **Wrong when written.** iOS was compiled and run on a Mac on 2026-09-10/11 and again on 09-14 (Xcode 26.6, iPhone 17 + 16 Pro **simulators**) — see `changelog-ios-validation-2026-09-10.md` and `ios-audit-report-2026-09-14.md`. What is actually outstanding: **never run on a physical iPhone**, and **not rebuilt since 2026-09-14**. Changes since then are Dart/backend only; the sole `ios/` edits are brand strings in the two Info.plists. | Needs a Mac with Xcode |
| 4.3 | **Test data in the dev database** — grew from 12 MB to 50+ MB during load testing; 43 trips remain stuck in `accepted`/`in_progress` from a run that predates the harness fixes. The fixed runs leave none | Nothing; needs a cleanup decision |

4.1 is worth doing before any capacity or cost planning, because it is the
number that determines how long a single box lasts.

---

## Stage 5 — Observability and ops actions (~1 week)

See [monitoring-and-actions-plan.md](monitoring-and-actions-plan.md).
Phase 1 is Stage 1 above. Phases 2 and 3 are the monitoring stack and the
action console. Phase 4 (Kubernetes) is assessed as **not yet needed** —
measured capacity is roughly 25–50k registered users on one box, against a 10k
target.

Highest-value single metric to add: **`dispatch_queue_depth`**, with an alert.
It is the number that moved first in every load test before riders felt anything.

---

## Stage 6 — Maintainability (~3 days)

See [frontend-maintainability-plan.md](frontend-maintainability-plan.md).
Split the 3,370-line `rider_app/home_page.dart` (35 widget classes in one file),
add contract tests between the backend DTOs and the hand-written
`shared_models`, and give `admin_app` its first tests.

None of this blocks feature work, and the design-system foundation is already
sound (~93% token discipline, zero arbitrary hex colours).

---

## Stage 7 — Feature gaps

From `UBER_GAP_ANALYSIS.md`, ordered by value rather than effort. The first
three are the ones a rider would notice immediately.

### Tier 1 — most visible

1. **Editable pickup.** Pickup is always the current location and cannot be
   changed. Flagged in the gap analysis as the high-value gap, and it blocks
   several others (map pin, venue pickup points, pickup notes).
2. **In-app masked calling.** Rider and driver cannot talk. Standard safety
   expectation.
3. **Driver and vehicle photos.** Initials only — affects trust at pickup.
4. **Wait timer and no-show flow.** The 150 m arrival geofence exists
   server-side (verified during load testing) but neither app has the UI
   (iOS audit P1 #13).

### Tier 2 — retention and completeness

5. Rebook a past trip — history is view-only.
6. Add a stop or change destination mid-trip.
7. Resend OTP with countdown.
8. Name and email at signup; profile photo.
9. Set-default and delete card.

### Tier 3 — growth and reach

10. Apple Pay / Google Pay.
11. Settings screens and internationalisation — there is no i18n at all today.
12. Referral codes.
13. Pool / shared rides; ride add-ons (pet, car seat, WAV, assist).

### Also outstanding

- **26 iOS backlog items** (6 P0, 14 P1, 6 P2) in the iOS audit.
- **4 cosmetic backend issues** (S6–S9): `/places/details` returns 502 rather
  than 400 on a bad placeId; multi-stop estimate polyline draws straight
  segments; the 429 body omits the `error` field other errors carry; a bad
  promo at create is silently dropped by design.

---

## Suggested sequencing

| When | What |
| --- | --- |
| **Today** | Stage 0 (commit + merge). Start Checkr onboarding and the SES production-access request — both wait on other people |
| **This week** | Stage 1 (latent bugs), Stage 3 quick wins (SMS/email switches, FCM Android, Stripe webhook secret) |
| **Next** | Stage 2 TLS, Stage 4.1 production benchmark |
| **Then** | Stage 5 observability, Stage 6 maintainability |
| **Ongoing** | Stage 7 features, highest tier first |
| **Needs a Mac** | Stage 2.2, Stage 4.2, iOS half of push |

The critical path to launch runs through the **external** items — background
checks and SES production access — not through engineering work. Start those
first; everything else is faster than they are.
