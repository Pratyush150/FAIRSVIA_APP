# FairsVia — The Architecture, Explained for a Non-Engineer

This document explains **how the app is built** — not the code, but the *meaning* of it:
which feature works how, which piece is responsible for what, and where to look when
something breaks. If you read this end to end, you should be able to hear a bug report
("the driver's car isn't moving on the rider's map") and know roughly **which part of
the system to suspect**.

It's written to be read top to bottom. Later sections assume the words defined earlier.

---

## Part 0 — The 30-second mental model

FairsVia is **three phone/web apps** talking to **one backend brain**:

- **Rider app** — a passenger books and pays.
- **Driver app** — a driver goes online, gets ride offers, drives the trip.
- **Admin app** — a web dashboard for your ops team (trips, users, pricing, live map).

Behind them sits the **backend** (the brain), which uses:

- **Postgres** = the *permanent filing cabinet*. Anything you'd be upset to lose (the trip happened, the fare was $18.40, the driver's earnings) lives here.
- **Redis** = the *fast scratchpad*. Things that change many times a second and are worthless a few seconds later (where each driver is *right now*, who's being offered a ride) live here. **Rule of the whole system: GPS never touches Postgres.**
- **A job queue (BullMQ)** = a *durable to-do list*. Work that must not be lost if a server restarts (a ride still hunting for a driver) is written here so it can resume.
- **A live phone-line (WebSocket)** = an *always-open connection* so the server can push "a driver accepted!" to a phone the instant it happens.

That's the entire shape. Everything below is detail on those pieces.

---

## Part 1 — The big pieces and what each is for

### 1.1 The apps (a Flutter "monorepo")
All the app code lives in **one repository** with three runnable apps and three shared libraries:

- `apps/rider_app`, `apps/driver_app`, `apps/admin_app` — the three programs.
- `packages/shared_models` — the **shared dictionary**: the agreed shape of a `Trip`, a map point, a user, a chat message. So rider and driver mean the exact same thing by "trip."
- `packages/core` — the **engine room** shared by all apps: talking to the server, holding your login, the live socket, screen routing, and whole ready-made screens (chat, history, account).
- `packages/design_system` — the **look and feel**: colors, fonts, buttons, the map widget. So all three apps look like one product.

**Why this matters for you:** login, the map, the API connection, and the data shapes are written **once** and reused. A fix or a rebrand (the app was renamed UberNav → RideVela → FairsVia) happens in one place, not three.

### 1.2 The backend (a NestJS "modular monolith")
The backend is **one program divided into ~30 modules, one per topic** — `auth`, `trips`, `dispatch`, `payments`, `chat`, and so on. Each module owns its feature. This is deliberate: it's simple to run (one program) but cleanly separated inside (so the "hot path" — matching — can be split out later as you grow).

### 1.3 The two databases — and why there are two
- **Postgres** (with Prisma, a translator between code and the database) — durable records.
- **Redis** — in-memory, microsecond-fast, and can **auto-forget** stale data.

A moving fleet sends GPS several times per second per driver. Writing that to Postgres would hammer it and be pointless — a position from 4 seconds ago is garbage. So live positions live in Redis, which also means **a driver whose phone dies simply expires and vanishes from matching** on its own.

> ⚠️ One honesty note: the code comments mention **PostGIS** (a geographic add-on for Postgres) as "used in later phases." In reality it is **not used** — all locations are plain latitude/longitude numbers, and nearby-driver search is done entirely in **Redis**. Not a bug, just a stale comment to be aware of.

### 1.4 The job queue (BullMQ) — why
Some work must survive a crash. If the server reboots while a ride is hunting for a driver, that ride must **resume**, not vanish. A queue is a durable to-do list (stored in Redis) with three lists:
- **dispatch** — the ride-matching loop.
- **notifications** — sending pushes/SMS/email.
- **scheduled** — "book a ride for 5pm" (held until the time, then released).

If a worker crashes mid-job, the job is retried and any server copy can pick it up.

### 1.5 The live connection (WebSocket / Socket.IO) — what it is
Normal web traffic (**HTTP**) is like **letters**: the phone asks a question, the server answers, the line closes. The server can't start a conversation. That's fine for "show my profile," useless for "a driver just accepted — *now*."

A **WebSocket** is a **phone line that stays open**: once connected, either side can speak any time. FairsVia uses **Socket.IO** (a robust library on top of WebSockets that adds auto-reconnect and "rooms"). This is how the server *pushes* live events to phones. **This is the single most important concept for understanding the live features.**

---

## Part 2 — How the core mechanisms work (the "how does X actually work" section)

### 2.1 The two channels between phone and backend
Every app talks to the backend two ways:
1. **REST (request/response, over HTTP)** — for "do this and tell me the result": log in, get a fare estimate, load chat history. Built with a library called `dio`.
2. **WebSocket (live push)** — for "tell me the moment something happens": ride offers, driver location, new chat messages.

Think: **REST = asking a question; WebSocket = a walkie-talkie left on.**

### 2.2 How login works (OTP + JWT)
- You type your **phone number** → backend generates a **6-digit code (OTP)** and sends it by SMS. It stores only a **scrambled (hashed) copy** of the code in Redis, with a short expiry, and limits attempts (5 per window) so nobody can brute-force it.
- You type the code → backend checks it, creates/loads your account, and hands back two **tokens (JWTs)**: a short-lived **access token** (15 min) you attach to every request, and a longer **refresh token** (30 days) used to silently get a new access token.
- **In dev mode there's no real SMS** — the backend hands the code straight back and the app shows it in a little "Dev code" chip. In production a real SMS provider sends it.

**How the token rides along:** a piece of middleware (`auth_interceptor`) automatically stamps `Authorization: Bearer <token>` on every request. If a request comes back "401 = your token expired," it silently refreshes and retries **once** — so you're never logged out mid-tap.

### 2.3 How the map + the moving car work
- The map is one shared widget (`AppMap`) wrapping **Google Maps**. You give it points (pickup, dropoff, driver), a route line, and a camera frame.
- **The gliding car ("puck"):** GPS only arrives every 1–2 seconds, which would make the car *jump*. So when a new position comes in, the widget **animates the car smoothly** from old spot to new over 900 milliseconds, and **rotates** it to point the way it's driving — exactly like Uber. That smoothness is a deliberate animation, not real GPS resolution.

### 2.4 How driver↔rider chat works (your example)
This is the mechanism you asked about, and it's a **hybrid**:
- When you **open** the chat, the past messages load over **REST** (`GET /trips/:id/messages`) — because history is a "fetch me the list" job.
- **New messages arrive live over the WebSocket** — the chat screen subscribes to the `trip:message` event, so a message the other person sends **pushes** onto your screen instantly.
- When you **send**, it goes over **REST** (`POST …/messages`); the backend saves it and **broadcasts it over the socket** to the other person.
- Messages are **de-duplicated by their ID**, so the socket "echo" of your own message doesn't show twice.

So: **socket for live delivery, REST for history and sending.** The messages themselves are **ephemeral** — kept in a Redis list, capped at 200, auto-deleted after 24 hours (chat isn't meant to be a permanent record).

### 2.5 How the screen "reacts" (the cubit pattern)
Each app uses small "brain" objects called **cubits** (e.g. `TripCubit`, `DriverCubit`). A cubit holds the **current situation as one snapshot** (called *state*) with a `phase` field. The screen's only job is to **draw whatever the snapshot says**. When something happens — you tap, or the server pushes an event — the cubit produces a **new snapshot**, and Flutter **automatically redraws** the parts that care.

Example, rider side: the phase walks
`idle → choosingRide → searching → driverEnRoute → driverArrived → onTrip → completed`.
When the socket delivers `trip:accepted`, the cubit flips the phase to `driverEnRoute`, and the bottom sheet **automatically** changes from "Finding your driver" to the driver's info card. **You never see code "change the screen" — the screen just follows the phase.** This is why, to debug a stuck screen, you ask *"what phase is the cubit in, and what was the last socket event?"*

---

## Part 3 — One ride, step by step (feature → which piece does it)

| # | What happens | Which piece does it | How, in one line |
|---|---|---|---|
| 1 | **Estimate** — rider sees prices | `trips` + `pricing` + `surge` + `geo` + `comparison` | Route the trip, price every tier, add surge, show competitor estimates. No trip saved yet. |
| 2 | **Request** — rider books | `trips` (createTrip) | Saves a `Trip` row (status `requested`), makes the 4-digit start code, applies promo, kicks off matching. |
| 3 | **Matching** — find a driver | `dispatch` (a durable queue job) | Expanding-ring search over Redis for nearby free drivers. |
| 4 | **Offer** — ask a driver | `dispatch` → WebSocket | Locks the driver, pushes `trip:offer` to their app, waits ~10s for an answer. |
| 5 | **Accept** — driver taps yes | `dispatch` (assign) | Guards against double-booking, marks driver busy, pushes `trip:accepted` to rider + `trip:assigned` to driver. |
| 6 | **En route** — car approaches | `location` → WebSocket | Driver's GPS streams in; server relays `trip:driver_location` to the rider's map (the gliding car). |
| 7 | **Arrived** | `trips` (driverArrived) | Driver taps "arrived" → rider notified. |
| 8 | **Start (OTP)** | `trips` (startTrip) + `payments` | Driver enters the rider's 4-digit code → trip goes `in_progress` → card **hold** placed. |
| 9 | **In progress** | `location` (odometer) | Every GPS ping adds real driven distance via an atomic Redis step. |
| 10 | **Complete** | `trips` (settleFare) | Recomputes the final fare from the *actual* distance driven. |
| 11 | **Settle** | `payments` + `ledger` | Captures the card, splits 20% platform fee vs driver payout, credits the driver's balance, emails a receipt. |

Every step is written to an **append-only audit log** (`TripEvent`), so a dispute six months later can be reconstructed.

---

## Part 4 — The clever engines (the parts competitors can't easily copy)

- **Dispatch / matching** — instead of "grab the nearest driver," it searches in **growing rings** (3 km → 9 km), puts the rider's **favourite drivers first**, re-orders the closest few by **real road driving time** (not straight-line), and **offers to one driver at a time** with a 10-second timer. A **per-driver lock** guarantees two riders can never be promised the same driver. If everyone nearby is busy, it keeps **re-trying for 45 seconds** before giving up honestly.
- **Ghost-driver eviction** — if a driver's phone dies without saying goodbye, their stale position is quietly dropped the next time matching runs (anyone whose last GPS ping is older than 45 seconds is removed). So dispatch never wastes time offering rides to a driver who's actually gone.
- **The odometer** — while driving, the server measures **actual distance** with a tiny script that Redis runs **atomically** (nothing can interrupt it mid-calculation), ignoring impossible GPS jumps over 2 km. This is what lets you bill the real distance, not the estimate.
- **Surge** — Redis counts demand vs nearby supply per area and raises the multiplier (capped) automatically, with an admin override.
- **The ledger** — driver earnings use **proper accounting**: an append-only list of signed entries (earning, tip, commission, withdrawal); the balance is always the **sum**, never an editable number. That's how the money stays trustworthy.

---

## Part 5 — What's REAL vs MOCK vs NOT BUILT (the status you asked for)

### ✅ Built and working today (has automated tests)
Full ride lifecycle · dispatch/matching · live tracking · OTP-verified start · odometer fare · pricing + surge · promo codes · two-way ratings · driver earnings ledger · in-trip chat · support tickets · notifications inbox · favourite drivers · scheduled rides · price-comparison (FairsVia) · admin dashboard · auth/OTP/JWT.
**Test coverage:** ~30 backend test files, ~49 end-to-end tests, ~15 Flutter tests — currently **167 unit + 48 end-to-end passing**.

### 🟡 Real, but only when you add the API key (mock by default)
These all work with a fake "mock" in dev and switch to the real service the moment you provide credentials — **no code change needed**:

| Feature | Real service | Turns on when you set |
|---|---|---|
| Card payments + driver payouts | **Stripe** | `STRIPE_SECRET_KEY` |
| Login-code texts | **Amazon SNS** (or Twilio) | `SMS_PROVIDER=sns` + AWS keys |
| Receipt emails | **Amazon SES** | `EMAIL_PROVIDER=ses` + AWS keys |
| Push notifications | **Firebase FCM** | `FCM_SERVICE_ACCOUNT_JSON` |
| Driver background checks | **Checkr** | `CHECKR_API_KEY` |
| Maps / routing | **Google** (or self-hosted OSM) | `GOOGLE_MAPS_API_KEY` |

> The one caveat: the Stripe code is complete but **hasn't been run against a live Stripe account yet** (waiting on test keys). Everything else in the mock→real switch is proven.

### 🔴 Not built yet (important — these are gaps, not bugs)
| Missing thing | Reality today | Why it matters |
|---|---|---|
| **Commercial insurance** | Entirely absent — no code, no field | **Legal launch blocker** in Florida (F.S. 627.748). Handled outside the app (a real policy), but nothing in the product references it. |
| **Real SOS / emergency** | Only writes an audit log + a shareable trip summary — **notifies no one, no 911, no emergency contact** | Do **not** market it as emergency response. Needs real building before launch. |
| **Referral program** | Absent (only generic promo codes) | A core growth mechanic — must be built. |
| **Turn-by-turn navigation** | Map shows a route line + moving car, but **no spoken/step-by-step guidance** | Drivers deep-link to Google Maps/Waze for now. |
| **Live re-routing** | Route is computed **once** at booking; nothing recomputes mid-trip | Traffic changes aren't reflected. |
| **Prepaid driver wallet / flat-fee model** | Absent — payments are card/cash with a **20% commission** split | This is the investor doc's model; **not** what's built. A real difference to resolve. |
| **Driver document upload** | Onboarding takes typed text only; verification is a **manual admin on/off switch** (auto-on in dev). No photo upload of licence/registration. | Real onboarding needs a document-upload + review pipeline. |

---

## Part 6 — Where the bugs most likely live (so you can reason about them)

Three areas are only **partially hardened** — safe in tests, but the **real-money paths still have gaps** to fix *before* handling real funds:

- **Capture + earnings not fully atomic (C1):** the driver's earnings entry is written just *after* the card is captured, not in the same all-or-nothing step — a failure in between could capture money but miss crediting the driver.
- **Payout race (C2):** the real Stripe payout reads the balance, then transfers, then records it — with no lock, two simultaneous payouts could double-pay.
- **Refund race (H1):** a refund can call Stripe *before* fully winning its database claim.

Still-open smaller items: **per-user promo limit** can be bypassed under heavy concurrency (H2); some admin/surge screens use a slow Redis `KEYS` scan (M5, fine to ~10k drivers); some fare-config money is stored as `Float` instead of exact `Decimal` (M13).

**None of these break the demo** — they're the "before you touch real money / real scale" list.

---

## Part 7 — How to find a bug yourself (a practical method)

When something's wrong, ask **"which of the four layers is it?"**:

1. **The screen looks wrong / stuck** → it's the **app / cubit**. Ask: *what `phase` is the cubit in, and what was the last socket event it received?* (Rider: `trip_cubit.dart`; Driver: `driver_cubit.dart`.)
2. **Live thing didn't happen** (offer never arrived, car not moving, chat not delivering) → it's the **WebSocket**. Ask: *is the socket connected? did the server emit the event to the right person's room?* (`realtime.gateway.ts`, `realtime.service.ts`; on the app, `realtime_client.dart`.)
3. **A "do this" action failed** (couldn't book, pay, load history) → it's a **REST call + a backend module**. Look at the module for that feature (`trips`, `payments`, `chat`…).
4. **Matching / "no drivers" / wrong driver** → it's **dispatch + Redis**. (`dispatch.service.ts`, and the Redis geo-set.)

**Symptom → suspect** quick table:

| Symptom | Most likely layer | Where to look first |
|---|---|---|
| Rider stuck on "Finding your driver" | dispatch | `dispatch.service.ts` (were there candidates? did anyone accept in 45s?) |
| Driver never got the offer popup | WebSocket delivery | driver socket connected? `trip:offer` emitted to `user:<driverId>`? |
| Car frozen on rider's map | location stream / socket | driver app sending `driver:location`? rider getting `trip:driver_location`? |
| "Payment could not be processed" | payments | Stripe keyed? the capture path in `payments.service.ts` |
| Login code never arrives | SMS provider | is `SMS_PROVIDER` real and keyed? (dev shows the code on screen instead) |
| Driver can't go online | drivers / background | is `docsVerified` true? (`DRIVER_AUTO_VERIFY` in dev) |
| Chat history empty but live works | REST path | `GET /trips/:id/messages` (socket is separate) |

---

## Part 8 — Where we are vs the plan (phase status)

- **Phase 1 — one-city MVP:** ✅ **essentially done.** Rider app, driver app, dispatch, trip lifecycle, wallet/ledger, cash + card, admin console, and localization scaffolding are built and tested end-to-end (validated on a real phone + emulator).
- **Phase 2 — commercial hardening:** 🟡 **partial.** Payments/SMS/email/push/background-checks/maps are all **coded and ready**, waiting only on API keys. Still to do for real launch: harden the three real-money paths (Part 6), build **real SOS**, **referrals**, **driver document upload**, and turn on the keyed providers.
- **Phase 3 — second market + FairsVia scale:** 🔜 the price-comparison feature exists (as honest *estimates*); the global "market pack" multi-country design from the investor doc is **not** built (and is a much larger, different project — see the investor-questions notes).

---

### The one-paragraph summary
FairsVia is **three Flutter apps + one NestJS backend**, with **Postgres** as the permanent record, **Redis** as the fast live memory, a **job queue** so work survives crashes, and a **WebSocket** so the server can push live events. The **ride, matching, money-accounting, pricing, chat and ratings are genuinely built and tested.** The **payment/SMS/email/push/maps/background-check integrations are built but need their API keys** to go from mock to real. **Insurance, real SOS, referrals, turn-by-turn navigation, live re-routing, a prepaid wallet, and document upload are not built yet.** And **three real-money code paths need hardening before you handle actual funds.**
