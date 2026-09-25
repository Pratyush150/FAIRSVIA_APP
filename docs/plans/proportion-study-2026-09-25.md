# Rider proportion study — 2026-09-25

Scope: only the map ↔ sheet split of each main rider screen in the Plan F "Map
Glass" build. Theme, colours, icons, content and order are untouched.

**How:** `apps/rider_app/test/proportion_study_test.dart` draws each screen at
each candidate over the painted stand-in map (the same one the Plan F
screenshot test uses). The route is fitted into whatever map is left above
the sheet, as the real camera fit does. Screens were drawn on a 411×914 phone
(the ratings below use these) and a 360×640 phone (checked for overflow and for
what is still visible). All candidates lay out without an exception on both.

```
PROPORTION_SHOTS=../../docs/brand/research/proportions \
  flutter test test/proportion_study_test.dart
```

Images are in `docs/brand/research/proportions/`: `<page>-<pct>.png` (411×914),
`<page>-<pct>-small.png` (360×640), `compare-<page>.png` (the candidates side
by side) and `winners-411x914.png` / `winners-360x640.png` (what ships).

**Scoring (0–10), all at once:** is the map useful (route, car and pickup in
view), can the key info be read without scrolling (price and Confirm; driver,
plate and PIN; total and Done), can the thumb reach the main button, how
balanced the screen is, and how close it is to what Ola and Uber do. I compared
against Ola and Uber from memory of their current layouts, **not** side by side
with screenshots. Those notes describe layout only.

**Caveat:** the map is a placeholder. I judged the space it gets, not the tiles.
None of this has been checked on a device or emulator yet.

## Results

| Page | Candidates → score | Winner |
|---|---|---|
| Home (idle), map header | 30 % → 6 · **35 % → 8** · 42 % → 7 | **35 %** (unchanged) |
| Choose a ride | 50 % → 5 · 58 % → 7 · **62 % → 8** | **62 %**, at least 480 px |
| Finding driver | **fit ≈ 27 % → 9** · 28 % → 7 · 35 % → 5 · 42 % → 3 | **fit content** (unchanged) |
| Driver en route | 36 % → 4 · 40 % → 7 · 42 % → 6 · **50 % → 8** | **50 %**, at least 400 px |
| Driver arrived | 36 % → 3 · 40 % → 5 · 42 % → 6 · **50 % → 9** | **50 %**, at least 400 px |
| On trip | **36 % → 8** · 40 % → 6 · 42 % → 6 · 50 % → 6 | **36 %**, at least 320 px |
| Ride completed | **85 % → 8** · 100 % → 6 | **85 %** (map peek) |

### 1. Home (idle): map header
- **30 % — 6:** the map is a thin strip. The recenter button crowds the sheet
  edge, and there is too little street context to confirm "you are here".
- **35 % — 8:** the search bar sits at about 58 % of the height, in easy thumb
  reach. Recents, services and the first promo all fit above the fold, and the
  map still shows the neighbourhood.
- **42 % — 7:** more map, but the services row drops to the fold and the promo
  mostly falls below it. On the idle screen the map is context, not the task.
- **Ola/Uber:** Uber's home is list-first with a small map or none. Ola's
  home gives the map roughly the top 40 %. 35 % sits between the two.
- (In the 30 % render the service art had not loaded because it was the
  first test to run. That is a timing artefact, not a proportion issue.)

### 2. Choose a ride (sheet opens at X, handle pulls it to 90 %)
- **50 % — 5:** only **one** tier shows above the pinned payment and Confirm
  footer, and Comfort fades under it, so you cannot compare prices without
  scrolling. On 360×640 **no** tier shows at all.
- **58 % — 7:** two tiers fully visible and the route is clear.
- **62 % — 8:** all three tiers show (XL's second line meets the footer fade)
  and the route and both pins stay in view above.
- Small screens: 62 % of 640 still left only a sliver of a tier, so the
  opening height is **at least 480 px** (`chooseRideMinPx`). On 360×640 that
  is 75 %: one full tier plus the start of the next. On tall phones 62 % wins.
- **Ola/Uber:** both open ride selection at roughly 55–65 % with 3 or more
  options showing and the route above. 62 % matches that.

### 3. Finding driver
- **Fit (≈ 27 % on 411×914) — 9:** status, ride, destination and Cancel,
  with no dead space. The route and pins get most of the screen.
- **28 % — 7:** the same content with a little empty glass.
- **35 % — 5 / 42 % — 3:** the extra height is an empty lower half of the card.
  The screen looks unfinished and hides map for nothing.
- **Ola/Uber:** both use a short "looking for drivers" card over a full
  map with a pulse. Keeping it content-sized matches that.

### 4. Driver en route / 5. arrived (one compact card, handle expands it)
- **36 % — 4 / 3:** the Ride PIN is cut in half. The PIN is the one thing the
  rider must read out.
- **40 % (the old value) — 7 / 5:** the PIN is fully visible. On *arrived* the
  primary **"I'm on my way"** button is hidden under the fade, and Message/Call
  are off screen.
- **42 % — 6 / 6:** half a button row peeks out, which reads as clipped.
- **50 % — 8 / 9:** driver, plate, car, PIN **and** the next actions (Message
  and Call en route; "I'm on my way" with Message and Call when arrived). The
  route, car and pickup still have the upper half.
- Small screens: 50 % of 640 cut off the PIN, so the card is **at least
  400 px** (`pickupCompactMinPx`, 62.5 % of 640). The PIN then shows in full.
- **Ola/Uber:** both give the driver-assigned card about half the screen,
  with plate, car and PIN (Ola's OTP) prominent and contact actions visible.

### 6. On trip (same card, now its own share)
- **36 % — 8:** it ends cleanly on the Details button. The status, ETA,
  Safety and Share show, and the map (the point of this phase) gets about 64 %.
- **40 % / 42 % — 6:** the "Add a stop" row half-peeks under the fade.
- **50 % — 6:** everything shows, but the map loses half the screen during
  the part of the ride where the rider mostly watches the car move.
- Small screens: **at least 320 px** (`onTripCompactMinPx`). On 360×640 the
  status, ETA and Safety/Share show, and Details sits just under the fold
  (one short swipe).
- **Ola/Uber:** both shrink the in-trip card to about 30–35 % and let the
  map dominate.
- This needed one change: en route and on trip used to share one compact
  value. They now have their own (`pickupCompact`, `onTripCompact`).

### 7. Ride completed
- **100 % — 6:** clear, but the lower half of the page is empty, and the trip
  vanishes. Nothing ties the receipt to the ride that just happened.
- **85 % — 8:** the same card with the finished route peeking above it, so it
  reads as *this* trip. Done is still pinned at the bottom in thumb reach, and
  it matches the floating-glass language of the other phases.
- **Ola/Uber:** both use a mostly full-screen rating and receipt page. Uber
  shows a small map thumbnail of the trip on it. 85 % gets the same "this
  trip" cue from the live map.

## What changed
- `apps/rider_app/lib/features/layout/rider_sheet_heights.dart` (new): every
  proportion in one place (`RiderSheetHeights.standard`), plus the pixel
  floors for short phones and a `debugOverride` test hook.
- `idle_home.dart`: reads `homeMap` there. The map framing already uses
  `IdleHome.headerHeightFor`, so it follows.
- `sheets/sheet_shell.dart` and `sheets/glass_phase_sheet.dart`: read choose
  ride, searching and completed from there (completed below 1.0 is a sized
  sheet, 1.0 is full screen). The live card uses `pickupCompact` or
  `onTripCompact`.
- Map framing: `home_page` already sets the map's bottom padding from the
  **measured** sheet height, so the route fit follows the new heights on its
  own. No change was needed there.
- Tests: the height assertions in `ride_sheets_a11y_test.dart` and
  `ride_sheet_layout_test.dart` now read `RiderSheetHeights`. The fake map
  moved to `test/support/fake_map.dart` (shared with the Plan F screenshot
  test), and the study test was added.
