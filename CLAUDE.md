# FAIRSVIA — Working Rules

These are binding operating rules for any AI/engineering work in this repo. They
override default behavior. Established by the project owner (Sai Kishore).

## 1. Absolute honesty
- Never fake, stub-and-claim-done, or paper over. If something is broken, say so
  with the evidence (logs, failing output). If a step was skipped, say that.
- State plainly what is verified vs. assumed. No hedging on things actually done;
  no false confidence on things not tested.

## 2. Do not silently reduce goals
- If a goal isn't achievable, say so explicitly and why — do not quietly drop it
  or swap in a smaller version and present it as complete.
- Known hard constraint: **iOS cannot be compiled or run on this Linux server**
  (needs macOS + Xcode). Keep code/config iOS-ready and commit it, but never
  claim an iOS build/run happened here. Android is validated on a real headless
  emulator (KVM-accelerated) on this box.

## 3. Architecture & code quality
- Maintain clean, segregated architecture: `backend/` NestJS modular monolith
  (one module per domain), Flutter monorepo with `packages/core`,
  `packages/design_system`, `packages/shared_models`, and `apps/*` kept separate.
- Shared, reusable UI/logic lives in `packages/*`, not copied per app.
- Scalable by default: Redis for hot/ephemeral data (never Postgres for GPS),
  Postgres+PostGIS for durable state, BullMQ for durable jobs, Socket.IO + Redis
  adapter for fan-out. Design so the hot path can be split out later.

## 4. Validate everything you build
- Every feature ships with tests: backend unit + e2e, Flutter `bloc_test`/widget.
- Drive changes end-to-end, don't just typecheck. Use the fake-driver simulator
  (`tools/fake-driver-simulator`) and load tests to run **simulations** of real
  ride flows before calling something done.
- Validate Android visually on the headless emulator (screenshot + adb input).

## 5. CI/CD
- Keep `.github/workflows/ci.yml` green and **expand it** as features land
  (new test suites, analyze, build gates). CI is the gate; do not merge red.
- Run the full local gate (backend build + jest + e2e, `flutter analyze` + tests)
  before committing non-trivial work.

## 6. Keep building — don't stop mid-list
- When given a task list, work through it autonomously to completion; commit
  incrementally with clear messages. Don't halt for confirmation on work already
  authorized.
- Heartbeat: while running long autonomous work, emit a liveness ping every
  ~15 min (see `.worklog/heartbeat.log`) so progress is observable.

## 7. Dev/prod separation (standing)
- The production profile is a separate, opt-in stack that must never touch the
  running dev stack. The real `backend/.env.prod` stays gitignored, never committed.

## 8. Separation from RideVela (standing)
- FAIRSVIA (this repo, `/home/nova-robotics/fairsvia_app`) is forked from RideVela
  (`/home/nova-robotics/ubernav`), which runs on the same box. Never modify
  `/home/nova-robotics/ubernav` or its containers (`ubernav_*`, `ridevela_*`,
  compose project `infra`), and never point FAIRSVIA at its database.
- No `docker system prune` (with or without `-a`).
- Never use a Prisma shadow DB (`prisma migrate dev`) against a live database.

## Picking this up fresh
- **Read `docs/session-handoff.md` first.** It carries the current state, the
  environment traps that fail in misleading ways (the `NODE_ENV` test-gate trap,
  the separate per-phone OTP limit, the moving LAN IP), what is verified vs
  assumed, and the corrections made to this repo's own documentation — two docs
  here were confidently wrong and were believed before being checked.
- **On a Mac (iOS):** `docs/mac-ios-pilot-handoff.md` — build + iPhone checklist.
- UI roadmap to 10/10: `docs/plans/ui-10-audit-plan.md` (from the owner's audit, each point checked in code).
- Then `docs/remaining-work-plan.md` for what is left, and
  `docs/field-testing-plan.md` for on-road verification.

## Environment quick-reference
- Repo: https://github.com/Pratyush150/FAIRSVIA_APP.
- Brand: FAIRSVIA (written exactly so). "Road-F" logo; "Ocean Blue" accent
  (`#1B4FD8` ink, `#2F6BFF`, `#5B9DFF`) with a coral warm accent replaces the
  teal/mint/gold of RideVela in the shipped glass look; UI text in Anek Latin
  (numbers stay Inter); rounder corners (10/16/22/28, sheets 32) and pill
  buttons. Animations and Home tile art were recoloured with
  `tools/brand/recolor_lottie.py` / `recolor_png.py` (re-run after importing
  new art). No competitor price comparison: fares come only from
  FAIRSVIA's own rate card.
- Flutter: `/home/nova-robotics/flutter/bin`. Backend runs in Docker
  (`docker exec fairsvia_backend ...`), compose project `fairsvia`, network
  `fairsvia_default`; containers `fairsvia_backend`, `fairsvia_postgres`,
  `fairsvia_redis`, `fairsvia_adminer`, `fairsvia_tunnel`. Host ports: Postgres
  5532, Redis 6479, Adminer 8180 (DB user/name/password `fairsvia`).
- Routing/geocoding: OSRM/Nominatim are NOT run by this stack by default (opt-in
  compose profile `own-routing`, ports 5100/8181). `backend/.env` points at the
  host's existing OSRM :5000 and Nominatim :8081 over HTTP, and uses Google geo
  via `GOOGLE_MAPS_API_KEY`.
- App IDs: rider `in.novarobotics.fairsvia.rider`, driver
  `in.novarobotics.fairsvia.driver` (Android + iOS), admin (Android)
  `in.novarobotics.fairsvia.admin`. Deep-link schemes `fairsviaapp-rider://` and
  `fairsviaapp-driver://` (not `fairsvia-*`, so they don't collide with the
  RideVela apps on the same phones). Launcher names "FAIRSVIA Rider" /
  "FAIRSVIA Driver".
- Backend API: `<LAN_IP>:3200/api/v1` —
  the box's address is DHCP and has changed (was `192.168.1.48`, now
  `192.168.1.69`). Resolve it with `hostname -I` rather than hardcoding;
  `make build-web` and the visual-check tools now do this themselves.
- Android SDK: `/home/nova-robotics/Android/Sdk`; JDK 17 at `/home/nova-robotics/jdks`.
- Headless emulator AVD: `pixel_uber` (android-35 google_apis x86_64, KVM).
- Web serve: `tools/webserve.py PORT dir` (admin 9190, rider 9191, driver 9192).
- Monitoring: `infra/monitoring/` — Grafana :3001, Prometheus :9099,
  Alertmanager :9093. Opt-in (compose project `fairsvia-monitoring`, containers
  `fairsvia_*`); never touches the dev app stack.
