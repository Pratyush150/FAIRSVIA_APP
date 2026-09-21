# Frontend Maintainability Plan

Status: **planned, not started.** Assessed 2026-09-18.

Question this answers: *can we change UI or add features easily, and did we
build the right infrastructure for it?* Short answer: the architecture is right;
friction is concentrated in three files and one missing safety net.

---

## What is already right (don't re-litigate these)

**Design tokens are real and actually used.** `packages/design_system` carries
`app_colors`, `app_typography`, `app_spacing`, `app_elevation`, `app_motion`
plus 22 shared widgets. Measured across all three apps:

| Signal | Count |
| --- | --- |
| `AppColors.*` token usages | 156 |
| Raw Flutter colors (`Colors.white`, `Colors.transparent`, …) | 12 |
| Arbitrary hex (`Color(0xFF…)`) | **0** |

~93% token discipline. A full rebrand — colours, spacing, type scale — is a
one-file edit that propagates to all three apps.

**No package drift.** All three apps depend on `core`, `design_system` and
`shared_models` by path. Nothing is copy-pasted per app.

**Backend is easy to extend.** 24 domain modules on one consistent pattern,
API versioned at `/api/v1`.

**CI is a real gate.** Dependency audit, migrations, type-check, unit, e2e,
`flutter analyze`, Flutter tests, release web builds for all three apps, and
live ride simulations.

| Area | Test files | Lines |
| --- | --- | --- |
| backend unit | 38 | 6,417 |
| backend e2e | 1 | 1,389 |
| packages/core | 22 | 2,235 |
| packages/design_system | 4 | 663 |
| packages/shared_models | 6 | 494 |
| rider_app | 12 | 2,811 |
| driver_app | 3 | 1,207 |
| **admin_app** | **0** | **0** |

---

## Item 1 — Split the god files (highest value)

| File | Lines | Widget classes inside |
| --- | --- | --- |
| `apps/rider_app/lib/home_page.dart` | **3,370** | **35** |
| `apps/admin_app/lib/home_page.dart` | 1,916 | 29 |
| `apps/driver_app/lib/home_page.dart` | 1,719 | 11 |

The rider app is 12 files / 6,249 lines, and **over half of it is one file**
holding 35 widget classes in shared scope. Effects:

- Restructuring anything on the rider home screen means working inside a
  3,370-line file.
- It is a merge-conflict magnet as soon as two people touch the rider app.

**Approach:** mechanical extraction into `features/<area>/widgets/*.dart`, a few
classes at a time. No behaviour change, no rewrite. The existing cubit tests
(`trip_cubit_test.dart`, 1,421 lines) protect behaviour throughout.

**Order:** rider → admin → driver. Rider first; it is the worst and the most
frequently edited.

**Definition of done:** no app file over ~400 lines; each extracted widget in a
file named after it; `flutter analyze` clean; cubit tests unchanged and green.

---

## Item 2 — Enforce the backend ↔ Flutter contract

`packages/shared_models` is **hand-written**: every `fromJson` is manual (a
deliberate Phase 0 choice — `app_user.dart` notes freezed can come later).

Nothing ties those models to the backend DTOs. Rename a field in a NestJS DTO
and:

- Dart still compiles.
- `flutter analyze` passes.
- CI goes green.
- It fails at **runtime**, as a cast error, in a user's hands.

This is the riskiest item because it is silent. The e2e and simulation suites
catch some of it, which is why it has not bitten yet.

**Options, cheapest first:**

1. **Contract tests** — assert each Dart `fromJson` against a captured sample of
   the real backend response; fail CI on drift. Smallest change, catches most.
2. **`json_serializable` / `freezed`** — the code already anticipates this;
   removes hand-written parsing bugs but still does not tie to the backend.
3. **Generate Dart models from the backend's OpenAPI schema** — the real fix,
   the most work. Requires the backend to emit a schema first.

Recommend 1 now, 3 when the API stabilises.

---

## Item 3 — `admin_app` has no tests

Zero test files, while it can refund payments, change surge, edit fares,
verify drivers and deactivate users. The app where a regression costs money is
the one with no safety net.

**Approach:** mirror `driver_app`'s cubit tests — `admin_cubit.dart` (343
lines) and `admin_api.dart` (709 lines) are the targets. Pairs naturally with
the Phase 1.3 audit-log work in
[monitoring-and-actions-plan.md](monitoring-and-actions-plan.md), since both
concern admin actions.

---

## How hard is each kind of change today?

| Change | Difficulty | Why |
| --- | --- | --- |
| Rebrand colours / spacing / typography | easy | one token file, propagates everywhere |
| Add or restyle a shared widget | easy | `design_system`, consumed by all 3 apps |
| Add a backend endpoint | easy | consistent module pattern, 24 examples |
| Add a new screen | easy | `features/` structure exists |
| Change business logic (pricing, dispatch) | easy | isolated modules, well tested |
| Restructure a home screen | **hard** | 3,370-line file, 35 widgets |
| Change an API field shape | **risky** | hand-written models, silent runtime break |
| Change admin app behaviour | **risky** | no test safety net |

---

## Order and effort

| Item | Effort | Notes |
| --- | --- | --- |
| 1 — Split rider `home_page.dart` | 1 day | do first; biggest daily win |
| 1b — Split admin + driver home pages | 1 day | same method |
| 2 — Contract tests for shared_models | 0.5 day | option 1; highest risk reduction per hour |
| 3 — admin_app cubit tests | 0.5 day | pair with audit-log work |

~3 days total. All incremental — none of it blocks feature work, and none of it
requires an architectural change.
