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

### 6.1 Live tracking rendering — car icon, shrinking line, re-routing (Uber-style)

All three behaviours live in the **shared** map (`packages/design_system/`), so the rider and driver
apps get them from one place:

- **Vehicle icon** — the driver marker is a **top-down car** drawn to a bitmap once in
  `app_map.dart` (`_makeDriverIcon`): a dark car body with a white halo + shadow and a lighter
  windshield marking the front. It **rotates to the travel bearing** and **glides** between GPS
  fixes (interpolated over ~900 ms) so it never jumps.
- **Shrinking route line** — as the car advances, the bold line **consumes behind it** and vanishes
  on arrival. The pure helper `packages/design_system/lib/src/widgets/route_progress.dart`
  (`splitRouteAtPoint`) projects the car onto the route and returns the *remaining* part (drawn bold
  in the brand green) and the *travelled* part (drawn faint grey). `app_map.dart` splits at the
  gliding car's live position every frame. Unit-tested in `route_progress_test.dart`.
- **Live re-routing** — if the driver leaves the drawn route (takes a different/shorter road), the
  apps re-fetch the optimal road route from the car's **live position** to its current target
  (pickup, then dropoff). Backend endpoint: `GET /places/route` (`backend/src/geo/places.controller.ts`,
  a thin read-only proxy over `GeoProvider.route`). Client trigger + throttle: `RerouteGate`
  (in `route_progress.dart`) — fires only when off-route beyond ~55 m, and not more than once per
  ~6 s / 25 m of movement / while a fetch is in flight, so it never hammers the directions API.
  Wired in `apps/rider_app/lib/home_page.dart` and `apps/driver_app/lib/home_page.dart`
  (`_maybeReroute`). The freshly re-routed line is preferred over the route planned at booking.

> ⚠️ **Turn-by-turn navigation is NOT built** — the app draws and re-fetches a route *line*, but
> there is no voice/lane guidance (no navigation SDK). Drivers follow the line or their own maps.

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

## 12. Every backend service in detail (the 26 modules)

The server is a **NestJS modular monolith**: one folder per domain under `backend/src/`, each with a
thin **controller** (HTTP/WS front desk) and a **service** (the real logic). Here is what each does
and *how* it's built. Files are under `backend/src/<module>/`.

| Module | What it does | How it's built (the mechanism) |
|---|---|---|
| **auth** | Phone-OTP login + JWT sessions | 6-digit OTP is **hashed** and stored in Redis with a short TTL + attempt cap (brute-force safe). On verify, issues a short **access token** (15 min) + a **refresh token** (30 d) whose hash is stored in Postgres and **rotated** on each use (reuse of an old one is rejected). SMS via a provider interface: `mock` (dev, code echoed) / `twilio` / `sns` (Amazon). |
| **trips** | Ride lifecycle + state machine | `trips.service.ts` creates the trip (Postgres), drives the `trip-state-machine.ts` (requested→matching→accepted→arrived→in_progress→completed), verifies the **start OTP**, and computes the **final fare from the metered odometer** at completion. Handles multi-stop (summed legs) and hands scheduled rides to the `scheduled` module. |
| **dispatch** | Match a rider to a driver | The heart. Reads **Redis GEO** sets of online drivers per tier, searches an **expanding ring (3→9 km)**, offers to one driver at a time under a **per-driver lock** (`SET NX PX`) with a **10 s offer TTL**, re-sweeps within a 45 s window, **evicts ghosts** (stale GPS), and gives **favourite drivers** priority. Runs as a **BullMQ** job so a crash resumes the hunt. |
| **pricing** | Fares per tier | Per-tier base/per-km/per-min config in Postgres (admin-tunable); computes each tier's fare from the route distance/time. |
| **surge** | Demand-based multiplier | A demand/supply grid over cells; multiplier capped (≤2.0) with an admin override floor. |
| **payments** | Money — Stripe | Manual **auth-hold → capture**, splits **platform fee % / driver payout**, **tips** (100% to driver), **refunds** (with proportional driver clawback, serializable), **Stripe Connect Express** driver payouts, **idempotency keys**, and **signature-verified, idempotent webhooks**. Cash mode supported. **Real when `STRIPE_SECRET_KEY` is set, mock otherwise.** |
| **geo** | Routes / places / geocoding | A `GeoProvider` interface with **provider precedence** chosen in `geo.module.ts`: **Google** (when `GOOGLE_MAPS_API_KEY` set) → self-hosted **OSM** (OSRM + Nominatim) fallback → deterministic **stub**. Endpoints: autocomplete, details, reverse, and `route` (used by live re-routing). |
| **location** | Driver GPS → Redis + odometer | Ingests the driver's GPS stream into Redis (never Postgres — GPS is hot/throwaway). A **Redis Lua script** accumulates on-trip distance atomically (the "odometer") that `trips` bills from. |
| **realtime** | The live socket | A **Socket.IO gateway** with the **Redis adapter** (so it scales across processes). Rooms: `user:<id>` and `trip:<id>`. Emits `trip:offer/accepted/driver_location/arrived/started/completed/message`; answers `trip:sync` to rehydrate after a dropped socket. |
| **ledger** | Driver earnings | Serializable balance per driver; every fare/tip/payout is a ledger entry. |
| **ratings** | Two-way ratings | Rider↔driver, one per trip; recomputes the average under a serializable transaction. |
| **favorites** | Favourite drivers | A rider's favourites **jump the dispatch queue** next time. |
| **promo** | Promo codes | Atomic, guarded redemption with per-user + global limits; admin CRUD. |
| **scheduled** | Book for later | A **BullMQ delayed job** promotes a `scheduled` trip to `requested` at its time, then normal dispatch runs. |
| **background** | Driver background checks | **Checkr** integration behind an interface; **real when keyed**, else a mock that auto-clears. |
| **notifications** | Push (FCM) + inbox | FCM HTTP-v1 provider (**real when a service-account JSON is set**, else mock/logs). A notification inbox + device-token registration endpoint. Uses a **BullMQ** queue. *(Client-side push is not wired yet — see honesty notes.)* |
| **email** | Transactional email | Amazon **SES** provider (real when AWS creds + `SES_FROM` set, else mock). Sends trip **receipts** best-effort. `@Global`. |
| **chat** | In-trip messages | REST for history + **Socket.IO broadcast** (`trip:message`), de-duplicated by id. Backed by Redis. |
| **support** | Support tickets | Tickets with threaded messages. |
| **comparison** | Price comparison card | **Modelled** Uber/Lyft/Empower estimates (NOT live quotes — self-disclaimed). |
| **safety** | SOS | **Audit-log only today**: writes a `trip_event`, logs a warning, returns a shareable trip summary. **No 911/contact dispatch.** |
| **drivers** | Driver profile/state | Onboarding, online/offline, presence, vehicle, `docs_verified` (a manual admin toggle / Checkr "clear"). |
| **users** | Rider profile | Profile edit + **saved places** CRUD. |
| **admin** | Ops endpoints | Dashboard stats, ops metrics, live map, list trips/users/drivers, **verify drivers**, plus **diagnostics**: a config snapshot + a **live read-only probe** (pings Google/Stripe/AWS) at `GET /admin/diagnostics` and `/admin/diagnostics/probe`. |
| **health** | Liveness | `GET /health` (checks DB + Redis) and Prometheus `/metrics`. |
| **common** | Shared plumbing | Config loader, guards/interceptors, and a **hand-rolled AWS SigV4 signer** (`common/aws/aws-sigv4.ts`) used by SNS (SMS) + SES (email) — no AWS SDK. |

**Provider modes are decided at boot** from `backend/.env`. Check the live state any time with the
diagnostics endpoint, or in the logs: `docker logs ubernav_backend | grep -Ei "provider|geo"`.

---

## 13. Docker, in depth (how the "kitchen" runs)

Everything server-side runs in **Docker containers** described by `infra/docker-compose.yml`. A
container is an isolated mini-computer with exactly the software it needs; `docker compose` starts
several at once and wires them together on a private network where they reach each other **by name**
(the backend talks to `postgres:5432` and `redis:6379`, not `localhost`).

**The containers (all prefixed `ubernav_`):**

| Container | Image | Port (host) | Purpose | Persistent volume |
|---|---|---|---|---|
| `ubernav_backend` | built from `backend/Dockerfile` (Node 22) | **3000** | The NestJS server | source bind-mount (hot reload) + `backend_node_modules` |
| `ubernav_postgres` | `postgis/postgis:16-3.4` | 5432 | Durable database | `pgdata` |
| `ubernav_redis` | `redis:7-alpine` | 6379 | Live/hot data + queues (append-only persistence on) | `redisdata` |
| `ubernav_adminer` | `adminer:4` | **8080** | Web UI to browse Postgres (open `http://localhost:8080`) | — |
| `ubernav_osrm` | `project-osrm/osrm-backend` | 5000 | Self-hosted routing (OSM) fallback | `./osm-data` |
| `ubernav_nominatim` | `mediagis/nominatim:4.4` | 8081 | Self-hosted geocoding (OSM) fallback | `nominatimdata` |

**The backend image** (`backend/Dockerfile`): starts from `node:22-bookworm-slim`, installs OpenSSL
(Prisma needs it), runs `npm install`, then `npx prisma generate` (builds the typed DB client), and
launches `npm run start:dev`. `docker-entrypoint.sh` runs DB migrations before the server starts. In
**dev** the container **bind-mounts your `backend/` folder**, so editing a `.ts` file hot-reloads the
running server — but `node_modules` stays a named volume so the container keeps its own installed deps.

**Volumes = the pantry that survives restarts.** `pgdata`, `redisdata`, `nominatimdata` keep their
data across `up`/`down`. `docker compose down` stops containers but **keeps** volumes; `docker
compose down -v` **wipes them** (fresh DB) — use with care.

**Everyday commands:**
```bash
cd infra
docker compose up -d                         # start everything (detached)
docker compose ps                            # what's running + health
docker logs -f ubernav_backend               # follow server logs
docker compose up -d --no-deps --force-recreate backend   # reload after editing backend/.env
docker compose restart backend               # bounce just the server
docker compose down                          # stop all (data kept)
```

**Resource requirements (measured on this box, idle):** the whole stack idles at **~1 GB RAM total**
(backend ~650 MB, the rest tiny) and near-zero CPU. Postgres + Redis + backend alone are featherweight
(a **2 GB** VM runs them). The heavy part is **Nominatim's one-time import** of the OSM extract (wants
~1 GB shared memory + a few GB of disk while importing) — after that it idles at ~200 MB. If you don't
need self-hosted maps (i.e. you use Google), you can skip `osrm` + `nominatim` entirely.

---

## 14. Deploying to the cloud (so it's up 24/7, not on the office PC)

Today the backend runs on this **office PC**, reached from the phones through a **Cloudflare tunnel**
(a public doorway to the PC). That works only while the PC is on, and a reboot changes the tunnel URL.
For a real "always-on, test anytime" setup, move it to a rented **cloud server**. Because everything is
already in Docker, the move is essentially *copy the compose file and run it*.

**Recommended: Oracle Cloud "Always-Free" (Ampere A1, ARM).**

| Spec | Free-tier allowance | What the app needs |
|---|---|---|
| CPU | up to **4 Ampere ARM vCPUs** | 1–2 is plenty for a pilot |
| RAM | up to **24 GB** | stack idles ~1 GB; 24 GB is huge headroom (covers Nominatim import) |
| Disk | up to **200 GB** block storage | ~20–40 GB is comfortable |
| Cost | **free forever** | — |

All our images (`postgis`, `redis`, `node`, `adminer`, `osrm`, `nominatim`) have **arm64** builds, so
the ARM VM is fine.

**Deploy checklist:**
1. Provision an **Ubuntu 22.04 ARM (Ampere A1)** VM on Oracle Cloud (or any always-on Linux VM).
2. `sudo apt install docker.io docker-compose-plugin` (install Docker + Compose).
3. `git clone` the repo onto the VM.
4. Create `backend/.env` with **real** keys (Google Maps, Stripe live/test, a real SMS provider, etc.).
   Set `NODE_ENV=production` — the config guard then **refuses to boot** with dev secrets or `SMS_PROVIDER=mock`, which is what you want.
5. `cd infra && docker compose up -d` — the whole stack comes up identically.
6. **Front it with TLS + a permanent hostname.** Either a **Cloudflare named tunnel** bound to a
   subdomain (survives reboots, fixed URL, no open ports) or **nginx + a real cert** on the VM. Point
   the apps at that fixed `https://…/api/v1`, build the APKs **once**, and they never go stale.
7. **Firewall:** expose **only** the HTTPS front door. **Never** expose Postgres (5432) or Redis
   (6379) to the public internet — keep them on Docker's internal network.

**What changes vs. the office setup:** nothing in the code. Only *where* it runs and the *URL* the
apps point at. That's the whole benefit of Docker here.

---

## 15. Debugging by layer (what each layer does + how to look inside it)

When something's wrong, work **top-down** through the layers and inspect each one directly.

| Layer | What it does | How to inspect it | Common failure |
|---|---|---|---|
| **Phone app (Flutter)** | Screens + cubits; draws the map | `adb -s <serial> logcat \| grep -iE "flutter\|ride"`; screenshot with `adb exec-out screencap -p > s.png` | Blank map (bad/no Maps key), stuck on default city (no GPS fix) |
| **Network** | App ↔ backend over HTTP + socket | On the app's backend URL: `curl <BASE>/health`. Real phone on mobile data uses the **public tunnel URL** (carrier DNS resolves it) | Wrong `API_BASE_URL` baked into the APK; tunnel down |
| **Backend (NestJS)** | All business logic | `docker logs -f ubernav_backend` — every request, dispatch decision, payment, and error prints here | 500s, provider errors, boot refusal (bad prod config) |
| **Redis (live)** | Online drivers, GPS, locks, queues | `docker exec ubernav_redis redis-cli` → `ZRANGE drivers:geo:economy 0 -1` (who's online), `KEYS trip:*`, `LLEN bull:dispatch:wait` | "No drivers" = the geo set is empty (driver not online/near) |
| **Postgres (durable)** | Trips, users, payments | `docker exec ubernav_postgres psql -U ubernav -d ubernav` then SQL; or the **Adminer** web UI at `http://localhost:8080` | Wrong fare/status = inspect the `trips` row |
| **Dispatch** | The match loop | Watch the backend log during a booking; check the offer key + lock in Redis | Offer never reaches a driver = no eligible driver, or a stuck lock |
| **Payments** | Stripe hold/capture/split | Backend log + the **Stripe dashboard** (test mode) → Payments/Connect | Tip/card fails "no payment method" = rider has no card attached (expected for cash/sim riders) |
| **Geo** | Routes/places | `curl "<BASE>/places/autocomplete?q=Miami"` (needs a token); `docker logs ubernav_backend \| grep -i geo` shows which provider is active | No suggestions/route = Google API not enabled on the key, or OSM extract doesn't cover the coords |
| **Realtime (socket)** | Live push | `curl "<BASE>/socket.io/?EIO=4&transport=polling"` returns a session id if the socket layer is healthy | Car doesn't move = socket not connected / driver not streaming GPS |

**The fastest triage tool** is the ride-flow table in **§4**: identify *which step* the symptom
belongs to, then open the file(s) that step names.

---

## 16. Test it yourself (a runbook for when no Claude session is running)

This is how to bring the whole thing up and run a ride on your own. It assumes the office PC is on.

**A. Is the backend up?**
```bash
curl http://localhost:3000/api/v1/health        # {"status":"ok",...} means the server + DBs are fine
cd /home/nova-robotics/ubernav/infra && docker compose ps   # all ubernav_* "Up"?
# if not: docker compose up -d
```

**B. Make it reachable from the phones (public URL).** Phones on mobile data need a *public* address,
not the LAN IP. The setup we use:
```bash
# 1) a small server that serves the APK downloads AND proxies /api to the backend:
node /path/to/proxy.js /path/to/apk-folder        # listens on :8090  (see the scratchpad proxy.js)
# 2) a Cloudflare quick-tunnel to it → prints a public https URL:
cloudflared tunnel --url http://localhost:8090
```
> ⚠️ A **quick-tunnel URL changes every time it restarts.** If it changes you must **rebuild the APKs**
> with the new `--dart-define=API_BASE_URL=<newurl>/api/v1` and reinstall. This is exactly why the
> **cloud deploy in §14 (with a permanent URL) is the real fix** — do that and this step disappears.

**C. Put the apps on two phones (wireless):** on each phone enable **Developer options → Wireless
debugging**, then:
```bash
adb pair <ip>:<pairPort> <6-digit-code>          # from the "Pair with code" dialog
# device auto-connects via mDNS; confirm:
adb devices -l
adb -t <transport_id> install -r <the .apk>
```
Rider APK → one phone, Driver APK → the other. Build the APKs with:
```bash
export PATH="/home/nova-robotics/flutter/bin:$PATH"
(cd apps/rider_app  && flutter build apk --debug --dart-define=API_BASE_URL=<publicURL>/api/v1)
(cd apps/driver_app && flutter build apk --debug --dart-define=API_BASE_URL=<publicURL>/api/v1)
```

**D. Log in (no real SMS in dev):** open the app, type **any** phone number, and the 6-digit code
**appears on screen** ("Dev code: …"). If it doesn't appear, the app can't reach the backend (step B).
Test accounts used so far: rider `305 555 0137`, driver `305 555 0142`.

**E. Run a ride:** Driver taps **Go online** → Rider **Where to?** → pick a destination → Confirm →
Driver **Accept** → watch the car move (icon + shrinking line) → Driver Arrived → Rider reads the
**OTP** → Driver enters it → **Complete**. Do this **outdoors** (GPS) with the **driver phone unlocked
and the app open** (Android throttles GPS when it's backgrounded).

**F. Or verify the whole loop with no phones at all** (proves the crux end-to-end against the live
backend):
```bash
cd tools/fake-driver-simulator && PAYMENT_MODE=cash node full-ride.mjs
# prints each stage: matching → offer → accept → location → arrived → OTP start → completed → fare split
```

**Honest caveat:** this office-PC + quick-tunnel setup needs a human to **restart the proxy + tunnel
after any reboot** (and rebuild APKs if the URL changed). It is *not* self-healing. The **cloud deploy
(§14)** is what makes it genuinely always-on and testable anytime without babysitting.

---

*See also: `docs/architecture-explained.md` (companion plain-language guide), `docs/codebase-audit.md`
(known bugs + improvements), `docs/map-and-eta-implementation-plan.md`, and `marketing/` (the Florida
go-to-market strategy).*
