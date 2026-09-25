# Session handoff — read this first

**Written 2026-09-22.** For whoever (or whatever) picks this project up next,
especially a fresh Claude Code session that has none of the previous session's
context. Everything here is in git; nothing depends on local machine memory.

The binding working rules are in `CLAUDE.md` at the repo root. Read those too —
particularly rule 1 (absolute honesty) and rule 2 (never quietly reduce a goal).

---

## Where the project stands

| Area | State |
|---|---|
| **Backend** | 436 unit tests / 42 suites, 48 e2e. All green. |
| **Flutter** | 417 tests, analyzer clean across all six packages. |
| **Android** | Continuously validated on the headless emulator (`pixel_uber`). Many end-to-end rides driven this session. |
| **iOS** | Builds and ran on a Mac (Xcode 26.6, simulators) on 2026-09-10/14. **Never on a physical iPhone. Not rebuilt since 09-14.** See `handoff-for-mac.md`. |
| **Monitoring** | Prometheus + Grafana + Alertmanager + Loki live in `infra/monitoring/`. Grafana :3001, Prometheus :9099. |
| **Admin console** | Operations only. Monitoring moved to Grafana. |

### What is genuinely left

**Updated 2026-09-23.** The authoritative list is **`remaining-work-plan.md`**
— rewritten that day. Key changes since this handoff was first written:

- **Market (corrected 2026-09-25): the pilot is Pune, India** — INR, km,
  +91, `Asia/Kolkata` (`MARKET=in` in the apps, `MARKET_CURRENCY=INR` on the
  server). The 2026-09-23 note here said "Uzbekistan first"; that is now a
  later market on the same switches (`uz`). The loaded routing data covers
  Maharashtra, which is what the Pune pilot uses.
- **Look:** Plan F "Map Glass" is final (2026-09-25) — the default build. Ship
  it with `make apk-rider` / `make apk-driver` (per-ABI, unshipped looks' art
  left out; see README "Release APKs").
- **Done and verified:** Sentry error tracking (backend + all 3 apps, off until
  a DSN is set), nightly Postgres backups with a restore drill and staleness
  alert, TLS automation in the prod stack, a privacy-policy draft.
- **Deferred by the owner:** anything needing the company's GST registration or
  company mobile number (SMS sender, payment/KYC vendors).
- **Store blocker found:** no in-app account deletion (Apple + Google require it).
- The real TLS certificate needs only a DNS record from the owner.

Field verification is tracked in **`field-testing-plan.md`** (23 cases, 13 of
them in a moving vehicle).

---

## Environment traps that cost real time

Every one of these was hit this session. They fail in ways that point somewhere
other than the cause.

### 1. `NODE_ENV` in the dev container breaks the test gate

The backend container pins `NODE_ENV=development`, so **jest does not default it
to `test`** the way CI does. That leaves the per-IP rate limiter live, and
suites fail on 429s that have nothing to do with the code. Ten e2e tests failed
this way and looked like real regressions.

`make test-backend` and `make test-e2e` now set `THROTTLE_DISABLED=true`. If you
run jest by hand, do the same:

```bash
docker exec -e THROTTLE_DISABLED=true ubernav_backend npx jest --ci
docker exec -e THROTTLE_DISABLED=true ubernav_backend npm run test:e2e
```

### 2. A second, separate OTP rate limit

Distinct from the throttler above: `auth.service.ts` counts OTP requests **per
phone** in Redis, 5 per TTL window. Scripted testing burns through it fast and
the failure is a bare 429. `THROTTLE_DISABLED` does **not** affect it. Clear it:

```bash
docker exec ubernav_redis sh -c "redis-cli --scan --pattern 'otp:rate:*' | xargs -r redis-cli del"
```

### 3. The box's LAN IP moves

DHCP. It was `192.168.1.48`, it is now `192.168.1.69`. Hardcoded in several
places, it failed as a connection-refused two layers from the cause.
`make build-web` and the visual-check tools resolve it at run time now. Always:

```bash
hostname -I
```

### 4. Release builds refuse `localhost`

`AppConfig` throws on a release build with no `API_BASE_URL`, and rejects
`localhost`. Pass the LAN IP:
`--dart-define=API_BASE_URL=http://<ip>:3000/api/v1`

### 5. The demo driver finishes a ride in ~90 seconds

Too fast to drive a manual UI sequence — four attempts to verify the Recenter
pill tap landed on the post-ride sheet instead. Use the tool added for this:

```bash
node tools/fake-driver-simulator/slow-ride.mjs 10   # crawls for 10 min, never completes
```

It holds the rider app in `onTrip` with a genuinely moving car. Clean up after:

```bash
docker exec ubernav_postgres psql -U ubernav -d ubernav \
  -c "UPDATE trips SET status='cancelled' WHERE status='in_progress'"
```

### 6. Driver setup is socket-based, not REST

`driver:status` and `driver:location` go over Socket.IO. There is no
`POST /drivers/me/status`. See `full-ride.mjs` for the correct sequence.

### 7. cAdvisor cannot work on this host

Docker uses the newer `overlayfs` storage driver; cAdvisor (≤ v0.52) looks for
`image/overlay2/layerdb`, fails to identify any container's read-write layer,
and registers **no containers at all**. It is deliberately absent from the
monitoring stack — don't "fix" the stack by adding it back. Per-service metrics
come from the backend's own `process_*`/`nodejs_*` series plus the Postgres and
Redis exporters.

### 8. Disk, and what must not be deleted

The box runs near full (96%). Safe to delete: Flutter `build/` and `.dart_tool/`
(13 GB reclaimed this session; `flutter pub get` restores them).

**Do not delete:**
- `infra/osm-data` (3.7 GB) — mounted live into the OSRM container. Routing and
  ETAs come from it.
- The ~52 GB of unused Docker images (`hailo8_ai_sw_suite`, `opendronemap/odm`,
  `colmap`) — those belong to the owner's **robotics/drone work**, not this
  project. A blanket `docker system prune -a` would destroy them.

---

## Things that are true but look wrong

- **`full-ride.mjs` fails its last assertion locally.** "platform fee null". The
  simulator's rider has no saved Stripe card, so capture fails against the live
  test key. The ride itself completes correctly. CI uses the mock gateway and
  passes. Not a regression.
- **`DiskSpaceLow` fires in Grafana.** True positive — the box really is at 96%.
- **`flutter_map` is still in `pubspec.yaml`.** The live map is
  `google_maps_flutter`. iOS needs a Maps API key in a gitignored
  `ios/Flutter/Secrets.xcconfig`, or the map renders **blank grey with no
  error**.
- **URL schemes are still `fairsvia-*://`.** Registered identifiers tied to the
  Stripe Connect return URLs, not branding. Renaming them breaks Connect.

---

## Verified vs assumed

Per rule 1, stated plainly.

**Verified by driving it:**
- Full ride lifecycle on Android, many times, with screenshots
- Ride-state copy at every phase
- Camera follows the car; look-ahead; route trims behind it
- Pan **or** zoom suspends following and raises the Recenter pill; tapping it
  returns the camera to the car, restores zoom, and resumes following (proven
  with `slow-ride.mjs`)
- Tip flow including the `tip: 0` receipt bug
- Kill switches over the API, audited; pausing dispatch defers a trip and
  un-pausing releases it
- Grafana: 5/5 targets up, 3 datasources healthy, all dashboard queries
  returning real data
- `/health`, `/health/live`, `/health/ready`

**Not verified:**
- **Anything on iOS.** No Mac here. iOS last built 2026-09-14.
- A true two-finger **pinch** — `adb` cannot drive multitouch. Double-tap zoom
  covers the same code path and works.
- Socket-drop / reconnect banner on a device (unit-tested only)
- Background-and-resume mid-ride on a device (code path exists, untested by hand)

---

## Useful commands

```bash
# Gate (run before committing non-trivial work — CLAUDE.md rule 5)
make test-backend && make test-e2e
for d in packages/* apps/*; do (cd $d && flutter analyze && flutter test); done

# Stacks
cd infra && docker compose up -d                                  # app
cd infra/monitoring && docker compose -f docker-compose.monitoring.yml up -d

# Android emulator
emulator -avd pixel_uber -no-window -no-audio -gpu swiftshader_indirect &

# Simulated rides
node tools/fake-driver-simulator/full-ride.mjs      # fast, asserts
node tools/fake-driver-simulator/demo-live-ride.mjs # waits for a real booking
node tools/fake-driver-simulator/slow-ride.mjs 10   # long window for UI work
```

Grafana **http://<LAN_IP>:3001** (`admin` / `ridevela` — change it). Keep the
**Ops** dashboard open during field testing; it turns "it felt slow" into
dispatch backlog and match-latency numbers.

---

## Corrections made to this repo's own documentation

Two documents were confidently wrong and were believed. Worth knowing the
pattern:

1. `remaining-work-plan.md` said **"nothing on iOS has ever been compiled."**
   Two earlier documents in the same folder describe real iOS builds. The claim
   was repeated back to the owner as fact more than once before being checked.
2. `handoff-for-mac.md` said no Podfile existed, that Stripe was on the mock
   path, and that **no Google Maps key was needed**. All three were stale; the
   last would have sent someone chasing a blank map.

Both are corrected. The lesson for the next session: **this repo's docs are not
automatically true.** Check claims against the tree before repeating them.
