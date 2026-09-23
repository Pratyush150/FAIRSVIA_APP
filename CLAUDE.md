# Ride App — Working Rules

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

## Picking this up fresh
- **Read `docs/session-handoff.md` first.** It carries the current state, the
  environment traps that fail in misleading ways (the `NODE_ENV` test-gate trap,
  the separate per-phone OTP limit, the moving LAN IP), what is verified vs
  assumed, and the corrections made to this repo's own documentation — two docs
  here were confidently wrong and were believed before being checked.
- **On a Mac (iOS):** `docs/mac-ios-pilot-handoff.md` — build + iPhone checklist.
- Then `docs/remaining-work-plan.md` for what is left, and
  `docs/field-testing-plan.md` for on-road verification.

## Environment quick-reference
- Flutter: `/home/nova-robotics/flutter/bin`. Backend runs in Docker
  (`docker exec ubernav_backend ...`). Backend API: `<LAN_IP>:3000/api/v1` —
  the box's address is DHCP and has changed (was `192.168.1.48`, now
  `192.168.1.69`). Resolve it with `hostname -I` rather than hardcoding;
  `make build-web` and the visual-check tools now do this themselves.
- Android SDK: `/home/nova-robotics/Android/Sdk`; JDK 17 at `/home/nova-robotics/jdks`.
- Headless emulator AVD: `pixel_uber` (android-35 google_apis x86_64, KVM).
- Web serve: `tools/webserve.py PORT dir` (admin 9090, rider 9091, driver 9092).
- Monitoring: `infra/monitoring/` — Grafana :3001, Prometheus :9099,
  Alertmanager :9093. Opt-in; never touches the dev app stack.
