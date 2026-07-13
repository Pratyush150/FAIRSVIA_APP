# UberNav

A faithful, Uber-style ride-hailing platform: **Flutter** apps (Rider, Driver, Admin) on a
**self-hosted NestJS + PostgreSQL/PostGIS + Redis** backend. Built in phases — see
`.claude/plans/glistening-jumping-toast.md` for the full plan.

## Status

- **Phase 0 — Foundations** ✅ — backend (auth + infra) and Flutter monorepo (3 apps + shared
  packages, phone-OTP login) built and verified end-to-end.
- **Phase 1 — Rider request flow** ✅ — Places autocomplete (backend proxy), fare estimate across
  tiers, trip create → `REQUESTED` with the trip state machine + audit log, and the rider map /
  where-to / choose-ride / finding-driver UI. Maps use a **stub geo provider** until you set
  `GOOGLE_MAPS_API_KEY` (see below).
- **Phase 2 — Realtime, dispatch & driver app** ✅ — Socket.IO gateway (JWT handshake, Redis
  adapter), driver GPS → Redis GEO, the dispatch **offer loop** (nearest-driver, per-driver locks,
  15s TTL), the full trip lifecycle (accept → arrive → start-OTP → complete) with WS events + audit
  log, the **driver app** (go online, interrupting offer modal, lifecycle), rider **live tracking**
  (driver marker + status), and a **fake-driver simulator**. Verified headlessly: a complete ride
  runs end-to-end over real Socket.IO (`tools/fake-driver-simulator/full-ride.mjs`).
- **Phase 3 — Payments & ratings** ✅ (backend) — marketplace payments behind a `PaymentProvider`
  interface: **auth-hold** the estimated fare on trip start → **capture** the final fare on
  complete → split a **20% platform fee vs 80% driver payout**. Tips go 100% to the driver;
  **cancellation fee** (₹30) applies only once a driver has committed (accepted/arrived).
  Two-way **ratings** (rider↔driver, one per trip, running average updated incrementally),
  **receipts**, and **payment methods**. Uses a **mock payment provider** by default; set
  `STRIPE_SECRET_KEY` to switch to the (untested) Stripe provider. Verified: 39 unit + 14 e2e
  tests, and `full-ride.mjs` now asserts the capture split, tip, receipt, and two-way ratings.
- **Phase 4 — Notifications, admin, app polish** ✅ — **push notifications** (mock provider →
  console; real via `FCM_SERVER_KEY`) fired on every trip milestone, with device-token
  registration. **Admin backend** (`/admin/*`, role-gated): dashboard stats, live/recent trips,
  users & drivers (with live online status from Redis), activate/deactivate — bootstrap an admin by
  listing their phone in `ADMIN_PHONES`. **Admin app v1 (Flutter Web)**: overview dashboard, trips,
  users (search + enable/disable), drivers (live status), auto-refreshing. **Rider/Driver payment &
  rating UI**: rider receipt + tip buttons + rate-driver stars; driver earnings + rate-rider. Socket
  **reconnection resilience** (`trip:sync` rehydrates the active trip on reconnect) on both apps.
  Dark mode (system) across all apps. Verified: 44 unit + 19 e2e (backend), rider/driver bloc tests
  green, admin app builds for web + live API checked.

## Repository layout

```
backend/     NestJS modular monolith (auth, users, ... more modules per phase)
infra/       docker-compose (Postgres+PostGIS, Redis, Adminer, backend)
apps/        Flutter apps: rider_app, driver_app, admin_app   (Phase 0, pending)
packages/    Shared Flutter packages: core, design_system, shared_models  (pending)
tools/       fake-driver-simulator (Phase 2)
```

## Running the backend (self-hosted, all in Docker)

```bash
cd infra
docker compose up -d --build
```

Services:
- Backend API — http://localhost:3000/api/v1
- Adminer (DB UI) — http://localhost:8080  (server `postgres`, user/pass/db `ubernav`)
- Postgres — localhost:5432 · Redis — localhost:6379

Health check:
```bash
curl http://localhost:3000/api/v1/health
```

### Auth flow (phone OTP → JWT)

In development the OTP is **printed to the backend console** and echoed back in the API
response as `devCode` (no real SMS is sent). Read it from `docker compose logs backend`.

```bash
BASE=http://localhost:3000/api/v1
# 1. request a code
curl -X POST $BASE/auth/otp/request -H 'Content-Type: application/json' -d '{"phone":"+919876543210"}'
# 2. verify it (use the devCode from the response) -> returns accessToken, refreshToken, user
curl -X POST $BASE/auth/otp/verify  -H 'Content-Type: application/json' -d '{"phone":"+919876543210","code":"1234"}'
# 3. call an authed route
curl $BASE/users/me -H "Authorization: Bearer <accessToken>"
```

### API endpoints (Phase 0)

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET  | `/health` | — | DB + Redis liveness |
| POST | `/auth/otp/request` | — | Send OTP (dev: console + `devCode`) |
| POST | `/auth/otp/verify` | — | Verify OTP → tokens + user |
| POST | `/auth/refresh` | — | Rotate refresh token |
| GET  | `/users/me` | JWT | Current user |
| PATCH| `/users/me` | JWT | Update name/email/photo |
| GET  | `/users/me/places` · POST | JWT | Saved places (Home/Work) |
| GET  | `/places/autocomplete?q=` | JWT | Places autocomplete (proxy) |
| GET  | `/places/details?placeId=` | JWT | Resolve place → address + coords |
| POST | `/trips/estimate` | JWT | Route + fare per tier |
| POST | `/trips` | JWT | Create trip → `requested` |
| GET  | `/trips/:id` · `/trips/history` | JWT | Trip(s) |
| POST | `/trips/:id/cancel` | JWT | Cancel (state-machine guarded) |
| POST | `/drivers/onboarding` · `/drivers/status` | JWT | Driver profile + go online/offline |
| GET  | `/drivers/me` · `/drivers/me/earnings` | JWT | Driver profile / earnings |
| POST | `/trips/:id/{accept,decline,arrived,start,complete}` | JWT | Driver trip actions |
| GET  | `/payments/methods` · POST | JWT | List / add a payment method (Phase 3) |
| POST | `/payments/:tripId/tip` | JWT | Tip the driver (100% to driver) |
| GET  | `/payments/:tripId/receipt` | JWT | Fare + payment split receipt |
| GET  | `/trips/:tripId/rating` · POST | JWT | Rate the counterparty / read your rating |
| POST/DELETE | `/notifications/devices` | JWT | Register / remove a push device token (Phase 4) |
| GET  | `/admin/stats` · `/admin/trips` · `/admin/users` · `/admin/drivers` | Admin | Dashboard data |
| PATCH| `/admin/users/:id/active` | Admin | Enable / disable a user account |

**WebSocket** (Socket.IO at the same origin, JWT in `auth.token`): client → `driver:location`,
`driver:status`, `trip:accept`, `trip:decline`, `trip:sync`; server → `trip:matching`,
`trip:offer`, `trip:accepted`, `trip:driver_location`, `trip:arrived`, `trip:started`,
`trip:completed`, `trip:cancelled`, `trip:no_drivers`.

### Simulator (test the full ride with no devices)

```bash
cd tools/fake-driver-simulator && npm install
npm run full-ride          # scripted rider+driver → asserts the whole lifecycle
DRIVERS=5 npm run simulate  # N roaming online drivers to match the real rider app against
```

### Google Maps key

The backend and rider app work with **no key** (deterministic stub geo). For real maps:
1. Backend: set `GOOGLE_MAPS_API_KEY` in `backend/.env` (enable Places + Directions), restart.
2. Rider app: paste your **Maps SDK for Android** key in
   `apps/rider_app/android/app/src/main/AndroidManifest.xml` (the `com.google.android.geo.API_KEY`
   meta-data), or pass the JS key for web in `web/index.html`.

### Tests

```bash
docker exec ubernav_backend npm test        # 44 unit tests (run inside the container)
docker exec ubernav_backend npm run test:e2e # 19 e2e tests against real Postgres + Redis
```

> Typecheck and test **inside the container** (`docker exec ubernav_backend ...`) — the bind-mounted
> `dist/` is owned by the container's root, so a host-side `npm run build` hits `EACCES`.

### CI/CD gate

```bash
make ci        # full local gate: backend build + unit + e2e, flutter analyze + tests
make ci-fast   # same, minus e2e (quick inner loop)
make shots     # headless-browser screenshots + health check of all 3 web apps
make help      # list all targets
```

The same checks run in GitHub Actions (`.github/workflows/ci.yml`) on every push/PR, plus a
release web-build of all three apps. New tests are auto-discovered (jest/flutter globs).

### Production deployment (opt-in, separate from dev)

The dev stack above uses hot-reload with a source bind-mount and a single
backend. For a production-style run there's a separate profile that builds a
compiled image and runs **two load-balanced replicas behind nginx** — it does
not touch the dev stack (own project name, own volumes, only nginx is published,
on `:8088`).

```bash
cp backend/.env.prod.example backend/.env.prod   # then set real secrets
cd infra
docker compose -p ubernav_prod -f docker-compose.prod.yml up -d --build
curl http://localhost:8088/api/v1/health          # served via nginx → a replica
docker compose -p ubernav_prod -f docker-compose.prod.yml down
```

- **`backend/Dockerfile.prod`** — multi-stage, prod-deps only, runs `node dist/main.js`
  as a non-root user; `migrate deploy` runs on start.
- **`infra/nginx/nginx.conf`** — reverse proxy + load balancer with WebSocket
  upgrade and `ip_hash` sticky sessions (so the Socket.IO handshake pins to one
  replica; cross-replica broadcasts still work via the Redis adapter).
- Multi-replica is safe because dispatch/notification work runs on BullMQ (each
  job processed once) and realtime uses the Socket.IO Redis adapter.

Still out of scope here: TLS termination (add certs at nginx) and real external
provider keys (SMS/Stripe/FCM).

### Observability

- **Structured logs** — pino JSON logs with a per-request correlation id
  (`x-request-id`, echoed in the response). Pretty output in dev, raw JSON in prod.
- **Prometheus metrics** — `GET /metrics` (outside the `/api/v1` prefix) exposes
  default Node process metrics + `http_requests_total` / `http_request_duration_seconds`.
  Point Prometheus/Grafana at it, or read the friendly rollup below.
- **Monitoring dashboard** — the admin app's **Monitoring** tab renders
  `GET /admin/metrics`: system (uptime/memory), HTTP throughput, BullMQ queue
  health (dispatch + notifications), and the trip funnel. Auto-refreshes every 6s.

### Database migrations

Schema is managed with **Prisma migrations** (not `db push`). On container start the entrypoint
runs `prisma migrate deploy`; CI does the same against a fresh DB.

```bash
# Change the schema:
#   1. edit backend/prisma/schema.prisma
#   2. generate + apply a migration (needs the running stack):
make migrate NAME=add_surge_zones     # = prisma migrate dev --name add_surge_zones
#   3. commit the new backend/prisma/migrations/<timestamp>_add_surge_zones/ folder
```

## Running the Flutter apps

The workspace is a pub workspace (single lockfile). Flutter 3.44 / Dart 3.12.

```bash
flutter pub get                 # from repo root — bootstraps all packages + apps

# Rider / Driver (mobile) — needs an emulator or device.
# Android emulator reaches the host backend at 10.0.2.2:
cd apps/rider_app  && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
cd apps/driver_app && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1

# Admin (web) — runs in a browser, reaches the backend at localhost:
cd apps/admin_app  && flutter run -d chrome
```

Login: enter any phone (e.g. `+919876543210`), tap Continue, then read the 4-digit code from
the OTP screen's dev hint (also in `docker compose logs backend`) and enter it.

### Monorepo layout
- `packages/shared_models` — pure-Dart domain models (`AppUser`, `AuthTokens`, `AuthSession`)
- `packages/design_system` — theme + widgets (`PrimaryButton`, `OtpInput`)
- `packages/core` — config, Dio + auth/refresh interceptor, secure token storage, DI (get_it),
  go_router auth gate, and the shared `AuthBloc` + phone/OTP screens (reused by all 3 apps)
- `apps/{rider,driver,admin}_app` — thin app shells supplying branding + post-login home

### Flutter checks

```bash
cd packages/core && flutter test                 # AuthBloc tests
cd packages/core && dart run tool/backend_smoke.dart   # live client <-> backend check
```

## Notes
- Access tokens expire in 15m; refresh tokens rotate on use (reusing an old one is rejected).
- Schema is managed with Prisma **migrations** (`prisma migrate deploy` on container start); the
  baseline is `backend/prisma/migrations/0_init/`. See "Database migrations" above.
- Secrets live in `backend/.env` (dev defaults). Change them before any non-local use.
