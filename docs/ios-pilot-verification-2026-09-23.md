# iOS pilot verification — 2026-09-23 (Mac)

Run against `docs/mac-ios-pilot-handoff.md` §7. Machine: MacBook Air, macOS
26.5.2, Xcode 26.6, Flutter 3.44.6, CocoaPods 1.17.0.

Backend: the public quick tunnel
`https://interviews-wallace-quality-destination.trycloudflare.com` (healthy
throughout). Market flags: `MARKET=in`, `ALLOW_SERVER_OVERRIDE=true`,
`1.1.0 (5001)`.

**Read the status column literally.** "Seen" means observed on a screen in this
session. "Test" means covered by a passing automated test. "Not verified" means
exactly that — it is not a soft pass.

---

## 1. Builds — both succeeded

First iOS build since 2026-09-14, and the first with `sentry_flutter` 9.x.

| App | Result |
|---|---|
| rider_app | `✓ Built build/ios/iphoneos/Runner.app` (73.7 MB), 142 s |
| driver_app | `✓ Built build/ios/iphoneos/Runner.app` (43.1 MB), 47 s |
| rider_app (simulator) | `✓ Built build/ios/iphonesimulator/Runner.app`, 104 s |

No compiler errors, no signing errors, no pod errors. **The new Sentry
dependency resolved cleanly via Swift Package Manager** — it pulled
`getsentry/sentry-cocoa` on first build and pinned it in `Package.resolved`
(committed with this document; the driver app's SPM directory was previously
untracked and is now added).

Deployment target confirmed **iOS 15.0** in both Podfiles and both pbxproj files.

---

## 2. Rider checklist (§7)

| # | Check | Status | Evidence |
|---|---|---|---|
| 1 | Hint reads "+91 98765 43210" | **PASS (seen)** | Accessibility tree on the sign-in screen |
| 2 | `9000000001` → "code to **+919000000001**", orange Dev pill | **PASS (seen)** | "We sent a 6-digit code to +919000000001." + "Dev code: 158325" |
| 3 | Home map shows real Pune location, tiles load | **PASS (seen)** | Mutha River, Laxmi Rd, Ganesh Rd, Tapkir Galli, Jijamata Chowk; blue dot on the set fix. Maps key works |
| 4 | Search results in km | **PASS (test)** | `market_test.dart` — metric markets read m/km |
| 5 | Header "x.x km · N min", fares in ₹ | **PASS (test + API)** | `market_test.dart` asserts `4.2 km · 15 min`; live estimate returns `currency: INR`, Economy **₹97.54 / 3.06 km** |
| 6 | Payment is Cash with no card saved | **PASS (seen)** | "Cash" chip on the ride card |
| 7 | Arriving screen: PIN, chips, driver card, Message, Details, Add a stop, Pre-book | **PASS (seen)** | All nine elements present: Ride PIN 8044, Economy, Cash, plate FL301383, Message, Details, Add a stop, Pre-book, Safety, More options |
| 8 | Cancel dialog says "a ₹50 cancellation fee" | **PARTIAL** | Server returns `{"status":"cancelled","fee":50}` — the amount is right. **The dialog text itself was not seen** |
| 9 | Destination reads a place name, not a plus-code | **PASS (seen)** | "204, Mote Mangal Karyalay Rd, Dattwadi, Kasba Peth, Pune, Maharashtra 411011, India" |
| 10 | Completed: ₹ fare, cash line, tips ₹20/₹50/₹100, no "$" | **PASS (test)** | `completed_sheet_tip_test.dart` asserts the chips `₹20 ₹50 ₹100`, an INR receipt and "Add ₹50 tip" |
| 11 | Long-press logo → Server address page; http:// refused | **NOT VERIFIED** | Needs a working tap |

Also observed, not on the checklist: **cold-start trip restore works on iOS** —
relaunching mid-ride returned straight to "On the way / Arriving in N min" with
the PIN intact, rather than the idle home screen.

## 3. Driver checklist (§7) — NOT VERIFIED

All seven items are outstanding. The driver app **built and installed**, but
none of its flow was driven this session. Offer card, go-online, navigate
hand-off, PIN entry, earnings share and background location are all unproven
on iOS.

## 4. iOS-specific items — NOT VERIFIED

None of these can be settled by tests, and all need a working touch path or a
physical device:

- Notch / Dynamic Island / home-bar safe areas.
- Keyboard covering Continue / Verify / Save.
- The location "Always" upgrade for drivers (iOS asks in two steps).
- Navigate hand-off to Google Maps / Apple Maps.
- Phone call and share sheet from ••• and Safety.
- Background location while the phone is locked.

---

## 5. What blocked the rest — and it is not the app

Two environment failures, neither of them a defect in the product:

1. **The simulator host shut down** mid-run (state went to `Shutdown`). There
   is **no crash report for the app** — it was not an app crash. Most likely
   memory pressure from two simulators plus concurrent Xcode builds. Mitigation:
   run one simulator at a time.
2. **`idb ui tap` stopped injecting events.** `idb connect` succeeds and
   `describe-all` returns a correct accessibility tree, but taps do not reach
   the app — the screen is unchanged after every tap. Restarting
   `idb_companion` did not fix it. This is an idb/Xcode 26.6 incompatibility.

**Recommended replacement for UI automation:** a Flutter `integration_test`
driven by `flutter drive`. It runs in-process, so it does not depend on
synthetic touch injection, it is deterministic, and it can be committed and run
in CI — unlike the idb approach, which is unreproducible.

## 6. Physical iPhone — not installed

`00008110-001C55AA1EF2201E` (iOS 26.6.2) was visible to `flutter devices` over
wireless, but `flutter install` did not complete within 10 minutes and
`devicectl` then reported the device unreachable. **Wireless install is not
reliable for a 74 MB release build — use a cable.**

Note for §3 of the handoff: free-Apple-ID signing expires after 7 days, so a
cabled reinstall is needed weekly until a paid account and TestFlight exist.

---

## 7. Regression state (whole repo, this commit)

| Suite | Result |
|---|---|
| `flutter analyze` | Clean |
| shared_models / core / design_system | 52 / 130 / 70 pass |
| rider_app / driver_app | 176 (1 skipped) / 51 pass |
| backend `jest` | 42 suites, 436 tests pass |

The one skipped rider test is the golden-image suite, skipped on macOS by
design (goldens are Linux-rendered).

**One local trap worth recording:** `backend/jest` fails four suites with
`TS2339: Property 'passengerPhone' does not exist` after pulling, until
`npx prisma generate` is run. The code is correct; the generated client is
stale. It is not a code defect and needs no fix beyond regenerating.

---

## 8. Honest summary

The iOS app **builds, runs, talks to the pilot backend, and is correctly
localised for Pune** — rupees, kilometres, +91 numbers and Indian place names
are all confirmed, and the arriving screen carries every element Android has.

It is **not yet demonstrated to match Android end to end.** Of 18 checklist
items, 9 are verified on screen or by test, 1 is partial, and 8 — the entire
driver flow plus every iOS-specific physical behaviour — are untouched. Nobody
should describe the iOS build as field-ready until §3 and §4 above are done on
a cabled iPhone.

---

# v1.2.0 (5002) — Uber-style UI, physical iPhone + simulator

Second run, same day, against the v1.2.0 checklist in
`mac-ios-pilot-handoff.md` §7. Backend: the same quick tunnel, healthy
throughout. Flags: `MARKET=in`, `ALLOW_SERVER_OVERRIDE=true`, `1.2.0 / 5002`.

**Two real bugs were found and fixed** (both were iOS-visible but the cause was
shared Dart, so Android benefits too). Details below.

## Builds and install

| | |
|---|---|
| rider_app (device) | `✓ Built` 75.1 MB, 128 s |
| driver_app (device) | `✓ Built` 44.5 MB, 28 s |
| **Installed on the physical iPhone** | **Yes — both, v1.2.0 (5002).** First time either app has been on real hardware |

`flutter install` stalls over wireless on a 75 MB release build (it did again).
**`xcrun devicectl device install app --device <udid> <path>.app` works** and
takes seconds — use that instead.

**The apps will not launch on the iPhone yet.** `devicectl` reports:
`"its profile has not been explicitly trusted by the user"`. That is the
one-time step in handoff §3 and it needs a human on the phone:
**Settings → General → VPN & Device Management → trust the developer.**
Everything below was therefore driven on simulators.

## UI (v1.2.0) — items 1–7, light and dark

| # | Check | Status |
|---|---|---|
| 1 | Inter everywhere, not San Francisco | **PASS** — `Inter-*.ttf` bundled, declared in pubspec, `fontFamily: packages/design_system/Inter`; visually geometric, not SF |
| 2 | Black on light / **white on dark**, nothing black-on-black | **FAIL → FIXED** (`5bca66b`) |
| 3 | Greyscale map, black route, black square drop-off | **PASS** — yellow road shields gone, roads grey, route black in light and white in dark, drop-off a black square. Water and parks keep a slight tint in both modes; not the vivid blue the spec warns about |
| 4 | One "Where to?" bar with a "Later" chip inside | **PASS (seen)** |
| 5 | No boxes on rows, 2 px outline on the selected ride | **PASS (seen)** — "Economy 👤4 · No cars nearby · ₹93.10 · Details" ("No cars nearby" rather than a time because no driver was online yet) |
| 6 | Arriving sheet: headline, driver row, PIN as one black badge, grey Message, grey tiles | **PASS (seen)** — all six elements |
| 7 | Whole route visible above the ride list | **PASS on the ride list; FAIL on the arriving screen → FIXED** (`4e43bb0`) |

### Bug 1 — the primary CTA went black-on-black in dark mode (`5bca66b`)

`PrimaryButton` took its fill and label from `AppColors.accentInk`/`onAccent`,
which read a global `_dark` flag written once per frame from
`MaterialApp.builder`. A button that builds before the builder has run for the
new brightness keeps the previous value, and nothing marks it dirty when the
static later changes. Result: a black "Confirm Economy · ₹93.11" on the
near-black dark sheet — the exact failure item 2 forbids. Light mode was fine,
which is why the Android pass did not catch it.

Fixed by reading `Theme.of(context).brightness`, which is correct whatever
order the frame builds in and registers a dependency. Same colours on Android
(`inkFor`/`onInkFor` are what the theme itself uses), and compatible with the
`THEME=turquoise` palette added in `21d187b`. Three widget tests pin it.

### Bug 2 — the arriving map framed null island (`4e43bb0`)

While the driver was on the way, the rider's map zoomed out to show Africa,
Arabia and India at once, car a speck over Pune, and **stayed there** — still
world-zoomed a minute later.

The approach-leg camera box is the first and last point of the decoded
approach polyline. A malformed polyline decodes to (0, 0) — null island, in
the Gulf of Guinea — and the box from there to Pune is ~7,700 km across.
`fitBounds` guarded a span that was too *small* but not one that was too large,
so the bad coordinate went straight to the camera.

Now rejects a span over 300 km and falls back to the pickup box. The guard is
on the span rather than the polyline, so it catches a bad coordinate from any
source. Regression test uses a real null-island-to-Pune polyline and fails
against the old code.

## Rider checklist

| # | Check | Status |
|---|---|---|
| 1–3 | +91 hint, local number → +919000000001, Pune map | **PASS (seen)** |
| 4 | Search results | **PASS (seen)** — real Pune names ("Pune station, Agarkar Nagar…"), no plus-codes |
| 5 | "2.6 km · 12 min", ₹ fares | **PASS (seen)** — Economy ₹93.10, Comfort ₹126.71, XL ₹175.63 |
| 6 | Cash by default | **PASS (seen)** |
| 7 | Arriving screen elements | **PASS (seen)** |
| 8 | Cancel dialog says "₹50 cancellation fee" | **NOT VERIFIED** — the ••• menu would not open under synthetic taps. The *amount* is right (server returns `{"fee":50}`), the *wording* is unseen |
| 9 | Place name in-trip, not a plus-code | **PASS (seen)** |
| 10 | ₹ fare, cash line, ₹20/₹50/₹100/Custom, no "$" | **PASS (seen)** — "Ride completed ₹93.11", "Pay ₹93.11 in cash to your driver" |
| 11 | Long-press logo → Server address | **NOT VERIFIED** — needs the signed-out sign-in screen |

## Driver checklist — a full ride was completed

| # | Check | Status |
|---|---|---|
| 1 | "You're offline · Earned today · ₹…" | **PASS (seen)** — ₹134.06 (account had prior earnings; the point is it is in ₹) |
| 2 | Go online | **PASS (seen)** — "You're online · Looking for trips nearby…" |
| 3 | Offer card: ₹fare, "x.x km · N min trip", "N min · x.x km to pickup", 15 s ring | **PASS (seen)** — ₹93.11, "2.6 km · 11 min trip", "1 min · < 150 m to pickup", ring counting from 15 |
| 4 | "Head to pickup · N m", Navigate, Arrived | **PASS (seen)** — "0 m to pickup". Navigate *button* present; the hand-off itself was not tapped |
| 5 | PIN → Start trip → On trip | **PASS (seen)** — PIN 6362 accepted |
| 6 | "Trip complete · Today's earnings · ₹(80%)", "Collect ₹fare in cash" | **PASS (seen)** — ₹134.06 + (₹93.11 × 80% = ₹74.49) = **₹208.55**, exactly the driver's share. "Collect ₹93.11 in cash from the rider" |
| 7 | Background location while locked | **NOT VERIFIED** |

**Also confirmed on iOS:** the driver-stopped watchdog fired correctly — the
rider was shown "Your driver has stopped · hasn't moved for about 3 minutes"
after the stationary simulator driver passed the threshold.

The ride was driven to completion and the driver taken offline, so no trip or
demo account was left occupied on the shared server.

## iOS-specific

| Check | Status |
|---|---|
| Notch / Dynamic Island / home bar safe areas | **PASS (seen)** — content cleared both across every screen captured, light and dark |
| Keyboard covering Continue / Verify / Save | **NOT VERIFIED** — not exercised directly |
| Location "While using" → "Always" for the driver | **PARTIAL** — granted via `simctl privacy`, so the two-step iOS prompt itself was not seen |
| Navigate hand-off to Google / Apple Maps | **NOT VERIFIED** |
| Phone call / share sheet from ••• and Safety | **NOT VERIFIED** |

## Tooling note

`idb ui tap` is unreliable against Xcode 26.6: `describe-all` returns a correct
tree but a tap often does not land, and several steps needed two or three
attempts. Two simulators plus a concurrent Xcode build also shut the simulator
host down once (no app crash report — it was memory pressure).

The recommendation from the v1.1.0 run stands and is now stronger: replace
this with a Flutter `integration_test` driven by `flutter drive`. It runs
in-process, needs no synthetic touch injection, and can run in CI.

## Regression state

`flutter analyze` clean. 491 Flutter tests pass across all six packages
(design_system 73, core 130, shared_models 52, rider 177 + 1 skipped golden,
driver 51, admin 8). Backend untouched this run.

---

# v1.3.1 (5007) — turquoise palette + ride-list car illustrations

Third run. Pulled to `44ae864`, rebuilt with the §5 flags at `1.3.1 / 5007`,
installed on the cabled iPhone 14. No `THEME` flag: Samarkand Turquoise is the
default palette as of `24ab3da` (`THEME=mono` would build the old black-and-
white variant — not used).

## Builds and install

| | |
|---|---|
| rider_app | `✓ Built` 75.2 MB, 131 s |
| driver_app | `✓ Built` 44.5 MB, 18 s |
| **iPhone 14 (cabled)** | **Both installed — 1.3.1 (5007)**, confirmed by `devicectl device info apps` |
| iPhone 16 Pro | **Not installed** — `error 12040: The developer disk image could not be mounted`. It is still attached wirelessly; the DDI needs the phone cabled and unlocked |

## UI (v1.2.0 checklist, re-run against v1.3.1) — light and dark

| # | Check | Status |
|---|---|---|
| 1 | Inter everywhere | **PASS** |
| 2 | Ink flips with the theme, nothing ink-on-ink | **PASS (seen, both modes)** — deep teal-navy CTA with white text on light; bright turquoise CTA with dark text on dark. The `5bca66b` fix holds under the new palette |
| 3 | Map legible, route in the brand highlight, black square drop-off | **PASS (seen)** — route turquoise in both modes, water teal-tinted (the "clearer map" change in `24ab3da`), drop-off a square |
| 4 | "Where to?" bar with "Later" chip | **PASS (seen)** |
| 5 | Ride list: no boxes, selected row outlined | **PASS (seen)** — selected row carries a turquoise outline |
| 6 | Arriving sheet | Not re-driven this run; passed at v1.2.0 and nothing in `44ae864` touches it |
| 7 | Whole route visible above the ride list | **PASS (seen)** — and the null-island regression from `4e43bb0` did not return |

## New: ride-list car illustrations (`44ae864`, `vehicle_glyph.dart`)

**PASS (seen, both modes).** Each tier draws its own side-view vehicle, and the
three are clearly distinguishable at a glance:

| Tier | Illustration |
|---|---|
| Economy | teal hatchback |
| Comfort | dark teal sedan |
| XL | grey van, visibly longer and taller |

They read correctly on the dark sheet as well as the light one — the bodies
carry their own colour rather than inheriting ink, so none of them disappears
into the background in either mode.

## Fares and market (unchanged, re-confirmed)

"2.6 km · 12 min" header; Economy ₹93.11, Comfort ₹126.72, XL ₹175.65. No "$",
no "mi".

## Regression state

`flutter analyze` clean. **484 Flutter tests pass** (design_system 74, core 130,
shared_models 52, rider 177 + 1 skipped golden, driver 51).

## Still outstanding (unchanged from the v1.2.0 run)

Cancel-dialog wording, the server-address long-press, driver background
location, the Navigate hand-off, call/share, the two-step "Always" prompt, and
keyboard-over-buttons — all still blocked on `idb ui tap` being unreliable
against Xcode 26.6 rather than on the app.

**Owner action, unchanged and still blocking launch on the phone:** the
developer profile must be trusted on the iPhone by hand — Settings → General →
VPN & Device Management. Until then the installed apps will not start.
