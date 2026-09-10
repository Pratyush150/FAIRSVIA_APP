# Ride App — a full Uber-style ride-hailing platform

This document explains **everything** about the app in plain language: what each part does,
how a ride flows from tap to receipt, where every feature lives, how to run and test it, and —
importantly — **how to figure out which step an issue is stuck in**. If you're new to the code,
read top to bottom once; after that, use it as a map.

---

## 1. What is Ride App? (the 30-second version)

It's a working clone of Uber. There are **three phone apps** and **one server**:

- **Rider app** — a passenger requests a ride, sees the price, watches the driver come, pays.
- **Driver app** — a driver goes online, gets ride offers, drives to the passenger, completes trips.
- **Admin app** — an internal web/Android panel for ops (approve drivers, refunds, see live activity).
- **Backend (server)** — the brain: matching riders to drivers, pricing, payments, live location,
  everything. The apps are "dumb screens"; the server decides.

Think of it like a restaurant: the **apps are the menu + table** (what customers touch), the
**backend is the kitchen** (where the real work happens), and the **databases are the pantry**.

---

## 2. The big picture (how the pieces fit)

```
   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
   │  Rider app  │      │ Driver app  │      │  Admin app  │   ← Flutter (Dart) phone/web apps
   └──────┬──────┘      └──────┬──────┘      └──────┬──────┘
          │  HTTP (requests)   │  + WebSocket (live) │
          └─────────────┬──────┴─────────────────────┘
                        ▼
              ┌──────────────────────┐
              │   Backend (NestJS)   │   ← the "kitchen": all business logic
              │  auth · trips ·      │
              │  dispatch · pricing ·│
              │  payments · geo ...  │
              └───┬───────┬───────┬──┘
                  ▼       ▼       ▼
             ┌───────┐ ┌──────┐ ┌────────────────────┐
             │Postgres│ │Redis │ │  Google Maps APIs  │
             │(durable│ │(fast,│ │ (routes, places,   │
             │ data)  │ │ live)│ │  geocoding)        │
             └────────┘ └──────┘ └────────────────────┘
```

Two ways the apps talk to the backend:
- **HTTP** = "ask a question, get one answer" (e.g. "what's the price?"). Like sending a letter.
- **WebSocket (Socket.IO)** = "a phone line that stays open" so the server can *push* live updates
  (driver moved, ride accepted) the instant they happen. This is how live tracking works.

---

## 3. The technology, explained simply

| Piece | What it is | Why we use it |
|---|---|---|
| **Flutter / Dart** | Google's toolkit to build iOS + Android + web apps from one codebase | One codebase, three platforms |
| **NestJS (Node.js/TypeScript)** | A structured framework for building the server | Organizes the "kitchen" into tidy modules |
| **PostgreSQL** | A durable database (data survives restarts) | Stores trips, users, payments — the permanent record |
| **Prisma** | A translator between our code and PostgreSQL | Lets us read/write the DB with type-safe code |
| **Redis** | A super-fast in-memory store (data is temporary) | Live driver GPS, "who's online", match locks — the hot stuff |
| **Socket.IO** | The "always-open phone line" (WebSocket) library | Push live updates to phones instantly |
| **BullMQ** | A durable job queue (runs on Redis) | Runs the matching job so a server crash doesn't strand a ride |
| **Google Maps SDK** | Google's map + navigation on the phone | The map you see, driver car, etc. |
| **Google Maps APIs** | Directions / Places / Geocoding web services | Routes, address search, "turn GPS into an address" |
| **Docker** | Runs the backend + databases in isolated "containers" | One command starts the whole kitchen |

**Golden rule of where data lives:** anything that must never be lost (a trip, a payment) →
**Postgres**. Anything fast and throwaway (a driver's current GPS, who's online) → **Redis**.

---

## 3.5 Understanding the stack from scratch (zero experience needed)

This section assumes you've never touched Flutter, Dart, or backend frameworks. Read it once and
the rest of the codebase will make sense.

### 3.5.1 The phone apps: Dart + Flutter

**Dart** is a programming language (made by Google). It's the language *all three phone apps* are
written in. If you know a little JavaScript or Python, Dart will feel familiar — variables,
functions, classes, `if`/`for`, etc. You don't need to master it; you need to *recognize* it. Dart
files end in **`.dart`**.

**Flutter** is the *toolkit* that turns Dart code into an actual app that runs on Android, iOS, and
the web — from **one** codebase. Instead of building an Android app and an iOS app separately,
Flutter draws the whole screen itself, so it looks the same everywhere.

**The one big idea in Flutter: everything is a "widget."**
A widget is just a piece of the screen. A button is a widget. A text label is a widget. A whole
page is a widget made of smaller widgets. You build a screen by **nesting** widgets inside each
other, like Lego bricks:

```dart
Column(                       // stack children vertically
  children: [
    Text('Where to?'),        // a label widget
    TextField(...),           // a text input widget
    ElevatedButton(           // a button widget
      onPressed: () { ... },  // what happens when tapped
      child: Text('Confirm'),
    ),
  ],
)
```

That code *describes* a screen with a label, a text box, and a Confirm button. Flutter reads that
description and paints it. When you hear "widget tree," it just means "the nested structure of
widgets that makes up the screen."

**Two flavours of widgets:**
- **StatelessWidget** — never changes after it's drawn (e.g. a static label).
- **StatefulWidget** — can change over time (e.g. a map that updates as the driver moves). It keeps
  some data ("state") and redraws itself when that data changes by calling `setState(...)`.

**"State" = the data a screen currently shows.** Example: on the rider home, the state includes
"where is the driver right now," "what's the ETA," "which ride tier is selected." When the state
changes (driver moved), the screen redraws to match.

**State management with bloc/cubit** (you'll see this everywhere in the code):
For anything beyond a trivial screen, we don't cram all the logic into the widget. Instead we use a
**Cubit** (from the `bloc` package) — think of it as the screen's **brain** kept *separate* from
its **face** (the widget). The cubit holds the state and the logic ("request a ride," "driver
accepted"); the widget just *shows* whatever the cubit's current state is and forwards taps to it.

- `TripCubit` (rider) and `DriverCubit` (driver) are the two big brains.
- The widget "listens" to the cubit; when the cubit `emit`s a new state, the widget rebuilds.
- Why bother? It keeps logic testable and the UI simple. When you see `trip_cubit.dart`, that's the
  rider's ride logic; `trip_state.dart` is the shape of the data it holds.

**`pubspec.yaml` and packages:** every Flutter project has a `pubspec.yaml` file — the "shopping
list" of outside code libraries ("packages") the app uses, e.g. `google_maps_flutter` (the map) or
`geolocator` (GPS). Packages come from **pub.dev** (Flutter's app store for code). Running
`flutter pub get` downloads them.

**The monorepo layout (`apps/` + `packages/`):** we have three apps that share a lot of code
(models, UI, networking). Rather than copy-paste, the shared code lives in **`packages/`** and each
app in **`apps/`** "imports" it:
- `packages/shared_models` — the data shapes (a `Trip`, a `RideOffer`, an `AssignedDriver`).
- `packages/design_system` — shared UI (buttons, cards, and the **`AppMap`** map widget).
- `packages/core` — shared plumbing (talking to the server, login, storage).
- `apps/rider_app`, `apps/driver_app`, `apps/admin_app` — the three apps, each mostly screens that
  wire those shared pieces together.

**Hot reload:** while developing, Flutter can inject code changes into the *running* app in ~1
second without restarting it. That's why Flutter development is fast.

### 3.5.2 The server: Node.js + TypeScript + NestJS

**Node.js** lets you run JavaScript/TypeScript *outside* a browser — e.g. on a server.
**TypeScript** is JavaScript plus "types" (labels that say "this is a number," "this is a Trip")
so mistakes are caught while coding instead of at runtime. Backend files end in **`.ts`**.

**NestJS** is the framework that organizes the server into tidy, repeatable pieces. Three words to
know:
- **Module** — a folder grouping one topic (e.g. `trips/`, `payments/`, `dispatch/`). Each domain =
  one module. This is the "one module per domain" structure.
- **Controller** — the "front desk." It receives HTTP requests and decides which function handles
  them. E.g. `POST /trips/estimate` lands in the trips controller.
- **Service** — the "worker" that does the real logic (calculate the fare, run the match). The
  controller is thin; the service is where the work happens (`*.service.ts`).

**Dependency injection (sounds scary, isn't):** instead of a service creating the things it needs,
NestJS *hands them to it* automatically. E.g. the dispatch service needs the database and Redis —
it just lists them in its constructor and NestJS "injects" them. This keeps pieces swappable and
testable (in tests we inject fakes).

### 3.5.3 Databases: SQL vs Redis, and Prisma

- **PostgreSQL (SQL)** stores data in **tables** — like spreadsheets with rows and columns. A
  `trips` table has one row per trip. It's on disk, so data **survives restarts**. Use it for
  anything permanent.
- **Prisma** is an **ORM** — a translator so we read/write those tables using normal code
  (`prisma.trip.findUnique(...)`) instead of raw SQL. The file `backend/prisma/schema.prisma`
  *defines* every table (this is the source of truth for the data shape).
- **Redis** stores data in memory as simple **key → value** pairs. It's extremely fast but
  **temporary** (mostly). We use it for live things: a driver's current GPS, the set of online
  drivers near a point (a "GEO set"), and short-lived locks during matching.

Rule of thumb again: **permanent → Postgres, live/fast/throwaway → Redis.**

### 3.5.4 How apps talk to the server: HTTP (REST) + WebSocket

- **HTTP / REST API** — request/response. The app sends a request to a URL (an "endpoint") like
  `POST /trips/estimate` and gets back one answer (the price). One question, one answer, done.
  "REST" is just a convention for naming those endpoints.
- **JSON** — the text format the request/answer is written in (a list of `"key": value` pairs).
  Both sides speak JSON.
- **WebSocket (via Socket.IO)** — a connection that **stays open**, so the server can push messages
  to the app the moment something happens (driver moved, ride accepted), instead of the app having
  to keep asking. Every live update in the app (`trip:offer`, `trip:accepted`,
  `trip:driver_location`) travels over this.

### 3.5.5 Login & security: OTP + JWT (in plain words)

- **OTP (one-time password)** — you type your phone number, the server texts you a 6-digit code,
  you type it back. That proves you own the number. (In development the code is shown on screen and
  no real SMS is sent.)
- **JWT (JSON Web Token)** — after OTP, the server gives the app a signed "wristband" (a token).
  The app shows this token on every future request to prove who it is, so you don't log in each
  time. Tokens expire and refresh automatically.

### 3.5.6 Docker (running everything with one command)

**Docker** packages a program plus everything it needs into a "container" that runs the same on any
machine. Our `infra/docker-compose.yml` starts several containers at once — the backend, Postgres,
Redis, and the map helpers — so you don't install each by hand. `docker compose up -d` = "start the
whole kitchen"; `docker logs ubernav_backend` = "watch the server."

### 3.5.7 Putting it together (one sentence)

The **Flutter/Dart apps** (screens = widgets, logic = cubits) talk over **HTTP + WebSocket** to the
**NestJS server** (modules → controllers → services), which stores permanent data in **Postgres**
(via **Prisma**), keeps live data in **Redis**, calls **Google Maps** for routes/places, and runs
inside **Docker** — with **OTP+JWT** guarding who's who.

---

## 4. A ride, step by step — and which part handles each step

This is the most useful section for debugging. If something breaks, find the step, then look at
the component/files listed. "R" = happens in the rider app, "S" = server, "D" = driver app.

| # | What happens | Where (component / files) |
|---|---|---|
| 1 | **Rider opens the app** → sees the Google map centered on their location | R: `apps/rider_app/lib/home_page.dart`, map widget `packages/design_system/lib/src/widgets/app_map.dart`, GPS `features/trip/location_service.dart` |
| 2 | **Rider types a destination** → Google Places suggestions appear | R: `features/trip/destination_search_page.dart` → S: `GET /places/autocomplete` → `backend/src/geo/*` (Google) |
| 3 | **Rider picks destination** → sees price for each tier (Economy/Comfort/XL) + a route | R → S: `POST /trips/estimate` → `backend/src/trips` + `pricing` + `geo` (Google **Directions** gives distance/time) |
| 4 | **Rider taps Confirm** → a trip is created in status `requested` | R → S: `POST /trips` → `backend/src/trips/trips.service.ts` (writes to Postgres) |
| 5 | **Server starts matching** → finds nearby online drivers | S: `backend/src/dispatch/dispatch.service.ts` (reads Redis GEO of online drivers) |
| 6 | **Server offers the ride to a driver** → driver's phone shows a full-screen offer | S → D (WebSocket `trip:offer`): shows rider name/rating + "~X km to pickup" · D: `apps/driver_app/lib/home_page.dart` |
| 7 | **Driver taps Accept** → rider gets "driver on the way" + live ETA | D → S → R (WebSocket `trip:accepted`): rider sheet shows "Arriving in N min", driver details, OTP code |
| 8 | **Driver drives to pickup** → their car glides on the rider's map | D streams GPS → S (`location` module) → R (WebSocket `trip:driver_location`); the car **interpolates + rotates** in `app_map.dart` |
| 9 | **Driver arrives + rider gives the 4-digit code** → trip starts (`in_progress`) | D: enters OTP → S: `POST /trips/:id/start` verifies the code |
| 10 | **Trip runs** → fare is metered by actual distance driven (the "odometer") | S: `backend/src/location/location.service.ts` (a Redis Lua script adds up distance safely) |
| 11 | **Driver taps Complete** → payment is captured, fare split | S: `backend/src/payments/payments.service.ts` (auth-hold → capture; 20% platform / 80% driver) |
| 12 | **Rider sees the receipt** → can rate, tip, favourite the driver | R: receipt sheet · S: `ratings`, `payments` (tip), `favorites` |

**So, "where is my issue?"** — examples:
- *No address suggestions?* → step 2 → Places API / backend `geo` / your Google key's "Places API".
- *"No drivers found"?* → step 5–6 → no online driver near the pickup, or dispatch (`dispatch.service.ts`).
- *Driver car jumps/doesn't move?* → step 8 → the driver's GPS stream or `app_map.dart` interpolation.
- *Price is wrong / $0?* → step 3 or 10 → `pricing` (estimate) or the odometer (actual distance).

---

## 5. Every feature, explained

**Rider**
- **Google map + your live location**, with a **recenter ("my location") button**.
- **Address search** (Google Places autocomplete) and **"set pickup on the map"**.
- **Price before you book**, across tiers (Economy / Comfort / XL / Premium), with a **surge ceiling**
  (prices can rise when busy but never past a published cap).
- **Price comparison** card (our fare vs *modeled* Uber/Lyft/Empower estimates — clearly labeled
  "estimates, not live quotes").
- **Multi-stop** rides (up to 3 stops), **scheduled rides**, **promo codes**, **cash or card**.
- **Live tracking**: driver car glides on the map, **"Arriving in N min"** ETA, driver name/photo/plate,
  **OTP start code**, in-trip **chat**, **cancel** (with fee once a driver has committed).
- **Receipt**, **rate driver**, **tip**, **favourite driver** (they get priority next time).

**Driver**
- **Go online/offline**, **presence heartbeat** (stays matchable while parked).
- **Ride offers** with a countdown, the **rider's name/rating**, and **"how far to the pickup"**.
- **Accept/decline**, navigate to pickup, **Arrived**, **OTP start**, **Complete**.
- **Earnings ledger** + **payouts** (Stripe Connect), **trip history**, **rate rider**.
- **Background GPS** (keeps streaming location while online, even if the app is backgrounded).

**Admin**
- Approve/curate drivers (KYC/background-check review), **refunds**, fare/surge/promo config,
  **live ops monitoring**.

**Safety & payments (honesty note — read this)**
- **OTP ride-start, two-way ratings, live GPS tracking, driver+plate shown, background checks
  (via Checkr, when keyed)** are real.
- **Insurance is NOT in the code** and is legally required to launch — never advertise it until built.
- **"SOS" is only an audit-log entry today** — it does NOT call 911 or notify a contact. Don't market it.
- **Referrals are NOT built** (only promo codes). Payments/SMS/push/background-checks are
  **"real when you add the API keys, mock otherwise."**

---

## 6. Maps & location (the part you're actively working on)

- **On the phone**, the map is **Google Maps** (`google_maps_flutter`). The shared map widget is
  `packages/design_system/lib/src/widgets/app_map.dart` — it draws tiles, the route line, and the
  markers (pickup, dropoff, and the gliding driver car).
- **The Google key on the phone** is read from a **gitignored** file so it's never committed:
  - Android: `apps/<app>/android/secrets.properties` → `MAPS_API_KEY=...` (injected into the app manifest).
  - iOS: `apps/<app>/ios/Flutter/Secrets.xcconfig` → `MAPS_API_KEY=...` (read by `AppDelegate.swift`).
- **On the server**, routes/addresses come from **Google Maps APIs**, chosen in
  `backend/src/geo/geo.module.ts`: if `GOOGLE_MAPS_API_KEY` is set it uses **Google** (with a
  self-hosted OpenStreetMap **fallback** so a Google outage can't take geo down); otherwise OSM; else a stub.
- **Location** comes from the device GPS via `geolocator`. If permission is denied it falls back to a
  configurable city center (`--dart-define=FALLBACK_LOCATION`, default Miami).

> ⚠️ **iOS cannot be built on this Linux machine** (it needs a Mac + Xcode). The iOS map config is
> written and committed ("code-ready") but has **not** been compiled/verified here.

---

## 7. Project structure (where things live)

```
ubernav/
├── backend/                     # the server (NestJS)
│   ├── src/
│   │   ├── auth/                # phone-OTP login, JWT tokens
│   │   ├── trips/               # create trip, lifecycle, state machine
│   │   ├── dispatch/            # matching riders ↔ drivers (the offer loop)
│   │   ├── pricing/ · surge/    # fares + surge pricing
│   │   ├── payments/            # auth-hold, capture, split, tips, refunds (Stripe)
│   │   ├── geo/                 # Google/OSM provider: routes, places, geocoding
│   │   ├── location/            # driver GPS ingest → Redis, trip odometer
│   │   ├── realtime/            # Socket.IO gateway (live events)
│   │   ├── ledger/ · ratings/ · favorites/ · promo/ · scheduled/ · background/ (Checkr) · notifications/ (FCM)
│   │   └── admin/               # admin endpoints
│   ├── prisma/schema.prisma     # the database shape (tables)
│   └── .env                     # secrets (gitignored) — API keys, DB URL
├── apps/
│   ├── rider_app/               # passenger app
│   ├── driver_app/              # driver app
│   └── admin_app/               # admin panel (web + android only, no iOS by design)
├── packages/                    # shared Flutter code (used by all apps)
│   ├── core/                    # networking, auth, storage, shared screens
│   ├── design_system/           # shared UI incl. the AppMap widget
│   └── shared_models/           # data models (Trip, RideOffer, AssignedDriver, ...)
├── infra/docker-compose.yml     # runs backend + Postgres + Redis + OSRM + Nominatim
├── tools/fake-driver-simulator/ # scripts to simulate a driver for end-to-end tests
└── docs/                        # this + strategy, audit, and plan docs
```

---

## 8. How to run everything

**Backend + databases (Docker):**
```bash
docker compose -f infra/docker-compose.yml up -d          # start everything
docker logs -f ubernav_backend                            # watch server logs
# health check:
curl http://localhost:3000/api/v1/health                  # should return 200
```
Secrets live in `backend/.env` (gitignored). To use Google for routing/places, set
`GOOGLE_MAPS_API_KEY=...` there, then recreate the container so it picks it up:
```bash
docker compose -f infra/docker-compose.yml up -d --no-deps --force-recreate backend
docker logs ubernav_backend | grep "geo provider"         # should say "Using Google Maps geo provider"
```

**A Flutter app (on an emulator or phone):**
```bash
export PATH="/home/nova-robotics/flutter/bin:$PATH"
cd apps/rider_app
# emulator reaches the host backend at 10.0.2.2; a USB/wifi phone uses an adb reverse tunnel (see §9)
flutter run -d <device> --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```
The Google Maps key for the phone must be in `apps/<app>/android/secrets.properties` (gitignored).

---

## 9. How to test (this is how the ride was verified end-to-end)

**Automated:**
```bash
# backend unit tests + integration (e2e) — run inside the container
docker exec ubernav_backend npm test
docker exec ubernav_backend npm run test:e2e
# Flutter static analysis + tests
export PATH="/home/nova-robotics/flutter/bin:$PATH"
flutter analyze
(cd apps/rider_app && flutter test)
```

**On the Android emulator:**
```bash
emulator -avd pixel_uber -no-window -gpu swiftshader_indirect &   # boot headless
adb devices                                                       # wait for "device"
cd apps/rider_app && flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n in.novarobotics.ubernav.rider_app/.MainActivity
adb exec-out screencap -p > shot.png                             # screenshot to inspect
```

**On a real phone (wireless):**
```bash
adb pair <ip:pairPort> <code>        # from the phone's Wireless debugging screen
adb connect <ip:connectPort>
adb -s <serial> reverse tcp:3000 tcp:3000     # so the phone can reach the backend over the cable
# build with the tunnel URL, then install:
flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:3000/api/v1
adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk
```
> **Xiaomi/MIUI phones:** you must enable Developer options → **"Install via USB"** AND
> **"USB debugging (Security settings)"** (needs a Mi-account sign-in) or adb can't install/tap.

**Simulate a driver (for a full ride without a second phone):**
```bash
cd tools/fake-driver-simulator && node full-ride.mjs
```

---

## 10. Debugging guide — "which step is it stuck in?"

| Symptom | Likely step (§4) | Where to look |
|---|---|---|
| Map is blank/grey on the phone | 1 | Google Maps key missing/invalid in `android/secrets.properties`; check the key has "Maps SDK for Android" enabled + correct SHA-1 |
| Map shows the wrong city (e.g. Miami) | 1 | Location permission denied or not yet resolved → it used the fallback; tap recenter or grant location |
| No address suggestions when typing | 2 | Backend `geo` / Google **Places API** not enabled on your key; check `docker logs ubernav_backend` |
| Price is $0 or route missing | 3 / 10 | Google **Directions API** off, OR (server on OSM) the region extract doesn't cover those coords |
| "Finding driver…" forever / no drivers | 5–6 | No online+verified driver near the pickup; check Redis: `redis-cli ZRANGE drivers:geo:economy 0 -1` |
| Driver can't go online ("docs not verified") | — | New drivers need `docs_verified=true` (admin approves); it's a manual toggle by design |
| Driver car jumps instead of gliding | 8 | The GPS stream frequency or `app_map.dart` interpolation |
| App can't reach backend | any | Wrong `API_BASE_URL`, backend down (`curl .../health`), or (real phone) missing `adb reverse` |
| Login OTP never arrives | — | In dev the code is **shown on screen** ("Dev code: …") and SMS is mocked; real SMS needs Twilio keys |

**Handy commands while debugging:**
```bash
docker logs -f ubernav_backend                       # server logs (errors, dispatch, payments)
docker exec ubernav_redis redis-cli ZRANGE drivers:geo:economy 0 -1   # who's online (economy)
docker exec ubernav_postgres psql -U ubernav -d ubernav -c "select status from trips order by requested_at desc limit 1;"
adb -s <serial> logcat | grep -i flutter             # app-side crashes/logs
```

---

## 11. Honesty notes (so nobody ships a false claim)

- **iOS can't be built here** (Linux). iOS code/config is committed but unverified — needs a Mac.
- **Insurance** (legally required to launch) is **not implemented** — never claim it.
- **SOS** is an **audit-log entry only** — it does not call 911 or a contact. Don't market it.
- **Referrals** are **not built** (only promo codes).
- **Vendors are "real-when-keyed":** Stripe (payments), Twilio (SMS), Checkr (background checks),
  FCM (push), Google Maps — each is mocked until you add its key.
- **The in-app "price comparison"** uses **modeled** competitor prices, not live Uber/Lyft quotes —
  the card says so; keep it that way.

---

*See also: `docs/codebase-audit.md` (known bugs + improvements), `docs/map-and-eta-implementation-plan.md`,
and `marketing/` (the Florida go-to-market strategy).*
