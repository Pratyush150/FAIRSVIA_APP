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
| 5 | Header "x.x km · N min", fares in ₹, no comparison card | **PASS (test + API)** | `market_test.dart` asserts `4.2 km · 15 min`; live estimate returns `currency: INR`, Economy **₹97.54 / 3.06 km**, `comparison: null` |
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
