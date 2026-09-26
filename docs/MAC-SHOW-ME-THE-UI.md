# Mac: show the owner every screen, one by one (updated 2026-09-26, v2.15.0)

**Who this is for:** the Claude session (or person) on the Mac at
`/Users/parthbhimani/ubernav`. Follow it top to bottom. At every **SHOW** step,
stop, tell the owner what they're looking at and what to check, save a
screenshot, and wait for "next" before moving on.

Rules: never commit `ios/Flutter/Secrets.xcconfig`; never force-push; this Mac
only builds iOS — the backend and the fake drivers run on **nova-pc**
(`ssh nova-pc`, already set up here). Nothing in this file has been run on
iOS yet: Android 2.15.0 was checked on nova-pc's emulator and the owner's
Realme and vivo. Treat every row as "expected", not "already seen on an iPhone".

**Current version: 2.15.0 (build 7500)** or later for both apps. The look is the final
**Plan F "Map Glass"**, which is the default build (no THEME flag). Don't
build other THEME flags.

---

## 1. Get the latest code and the server address

```sh
cd ~/ubernav && git pull --ff-only          # pull to the latest main (2.15.0 or later)
URL=$(ssh nova-pc 'docker logs ridevela_tunnel 2>&1 | grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" | tail -1')/api/v1
curl -s "$URL/health"        # must print {"status":"ok",...}
mkdir -p ~/Desktop/ridevela-ui
```
Use the **https tunnel** URL, not the Tailscale `http://` one (iOS blocks
plain http in release builds). The quick-tunnel URL changes whenever
nova-pc's internet drops. If `/health` fails, run
`ssh nova-pc 'docker restart ridevela_tunnel'`, wait 10 s, and fetch the URL
again.

## 2. Build and start the rider app

```sh
open -a Simulator            # an iPhone 16/17 simulator
SIM=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl location $SIM set 18.5204,73.8567          # pilot area
cd ~/ubernav/apps/rider_app && flutter pub get && (cd ios && pod install)
flutter run --release -d $SIM \
  --dart-define=API_BASE_URL=$URL --dart-define=MARKET=in \
  --dart-define=ALLOW_SERVER_OVERRIDE=true \
  --build-name=2.15.0 --build-number=7500
```
If release mode isn't supported on the simulator, use `--profile`. For a
cabled iPhone, use its id from `flutter devices`.

Screenshot for every SHOW step:
`xcrun simctl io $SIM screenshot ~/Desktop/ridevela-ui/<NN-name>.png`

## 3. Rider tour

On **nova-pc**, run helpers from a second terminal when a step says so:
`F=~/ubernav/tools/fake-driver-simulator; P='START_LAT=18.5300 START_LNG=73.8475'`

| # | Do | SHOW — what the owner should see |
|---|---|---|
| 01 | App opens | Splash: RideVela mark + a **teal animated loader**, gone in ≤1.5 s |
| 02 | Sign in: any 10-digit number → Continue → type the **"Dev code: 123456"** shown on screen → name → allow location | Home |
| 03 | Home | Floating frosted **"Where to?"** bar with a **teal→mint gradient ring that keeps turning** and a soft glow. The leading icon is an **animated location pin** (plays once). "Later ⌄" sits on the right |
| 04 | Scroll Home | Recent places; the **Ride / Pre-book / For others / Saved places** photo tiles, each with a thin teal rim; a **swipeable poster strip** (Offers, Plan tomorrow's ride, Help is one tap away, Let family follow your ride) that moves on every 5 s, has dots, and **shimmers** every ~6 s; promo banners below. No city name in any marketing copy |
| 05 | Press and hold a tile or poster | It shrinks slightly and **glows teal** |
| 06 | Bottom nav → **Offers** | The Offers tab icon is an **animated gift** (it also plays in the page header). Real codes: WELCOME50, AIRPORT100, WEEKEND20 |
| 07 | Account → Appearance | Light / Dark / Same as phone. It must recolour instantly at any time, **including mid-ride**, without resetting the ride |
| 08 | Where to? → type a place | Each result shows its **distance (e.g. "2.4 km") under the pin on the left**. Type nonsense → animated **"No places found"**. While loading → teal loader, not a grey spinner |
| 09 | Pick "Shivajinagar District Court" | **Choose a ride**: 4 tiers, **all white cars, shown whole (not cropped)**: Economy hatchback, Comfort sedan, Premium sedan, XL SUV. All tiers are bright. Picking one → **animated tick + small bounce**. Cash / Card sits above Confirm |
| 10 | Drag the Choose-ride sheet fully up | Not empty: **Compare rides** (seats · pickup · fare per tier), **About this fare** (distance, minutes, surge line), **Safety on every ride** tiles, posters |
| 11 | "Later ⌄" (or the Pre-book tile) | **Pre-book**: a standard **12-hour clock with AM/PM** (no 24 h dial), and **Cash / Card chips**. With no card saved it starts on Cash and Card says "Add card". It books and confirms |
| 12 | nova-pc: `ssh nova-pc "cd $F && $P node idle-driver.mjs 3"`, then Confirm | **Finding your driver**: radar rings on the map, glued in place while you pan. The search runs for up to 3 min |
| 13 | Drag that sheet fully up | What you booked (car picture, fare, payment), route, "Cancelling now is free", Stay safe tools, while-you-wait tips, posters |
| 14 | Cancel; nova-pc: `ssh nova-pc "cd $F && $P APPROACH_S=240 WAIT_AT_PICKUP_S=120 node slow-ride.mjs 3"`; book again | **Driver on the way**: plate biggest, car, name + ★, Ride PIN, Call + Message. Pulled up: a **car gliding toward a pickup pin** as the real ETA falls, "At your pickup by h:mm AM/PM", route, payment, safety tools (the **SOS tile pulses red**), meeting tips, posters |
| 15 | Driver arrives | "has arrived" with an **arrived animation** |
| 16 | Trip starts | "On the way to …" shown once; Safety, Share and Call. Pulled up: **Trip progress** with a **car sliding along the bar**, arrival time, your driver, safety tiles, trip details (fare, payment, promo), "Plan your ride back" poster |
| 17 | For a finished ride: `ssh nova-pc "cd $F && $P node demo-live-ride.mjs"`, then book | **Ride completed** at 75% of the screen: **full confetti burst** (no longer clipped), one "Total ₹…" line with Details, stars, tips (tap an amount = selected, tap again = removed, no extra confirm), **Done pinned**. Pulled higher: Your trip card, **Plan your return / Book this trip again**, Receipt / Get help, posters |
| 18 | Trips tab → tap a past trip | **Your trip** page: route map snapshot with distance/time pills, car + date + total, pickup→drop timeline, driver + plate, fare breakdown, payment, Share receipt / Get help |
| 19 | Map anywhere | **Solid pins**: teal pickup with a white dot, dark drop-off with a white square; your location is a **blue dot with a halo** |

## 3b. New in 2.13.0 (check these on iOS too)

| # | Do | SHOW |
|---|---|---|
| N1 | Cold-start either app | **Launch animation (~1.8 s)**: the RideVela wordmark fades in, a small car glides along a road line drawing a bright aqua route, then it fades into the app. No white flash between the native launch screen and the Flutter frame (the iOS LaunchScreen colour may need matching to #F7F8F9 light / #0E1114 dark; report it if it flashes) |
| N2 | Home | **Brighter aqua accent**: the "Where to?" ring turns teal→cyan→mint; selected items and pins are bright aqua; dark-mode buttons are vivid mint-teal. Backgrounds and text are unchanged |
| N3 | Bottom nav | **All four icons are animated** (Home, Trips, Offers gift, Account); the selected one is aqua inside a pill and replays once when tapped |
| N4 | Home "Ride" tile | An **everyday white hatchback** (no longer the sporty sedan) |
| N5 | Choose a ride | **All four cars are white, side-on and face LEFT**: Economy hatchback, Comfort sedan, Premium sedan, XL SUV |
| N6 | Choose a ride → "Book for someone else" (or the Home "For others" tile) | **Pick from contacts** opens the iOS system contact picker (no contacts-permission prompt, by Apple's design). Choosing a contact fills the name and the +91 number. Cancel leaves the fields alone |
| N7 | Choose a ride (Pune pickup, market INR) | **Price comparison**: one line above Cash/Card, "✓ Save ₹X vs Uber, Ola, Rapido ›" (only when we are really cheaper; otherwise "Compare prices with …"). Tap it → **Price check** card: RideVela row first (aqua), then "Uber · Ola · Rapido" grouped at the Pune RTA-approved fare, a "Cheapest" pill, and one footnote. Also the first section when the sheet is pulled up |
| N8 | Account → Credits & licences | Flutter licence page, including a "RideVela artwork" entry |
| N9 | Account → Help & support → raise a ticket | It appears in the **admin app's Support tab**; an admin reply shows back in the rider's ticket |

iOS-specific: `flutter_native_contact_picker` is a new plugin, so run `pod install` in both
`apps/rider_app/ios` and `apps/driver_app/ios` after pulling.

## 3c. New in 2.15.0: price check per provider and per cab segment

| # | Do | SHOW |
|---|---|---|
| P1 | Choose a ride (Pune pickup, e.g. Shivajinagar → Koregaon Park) with **Economy** selected | The line above Cash/Card reads "✓ Save ₹X vs Uber, Ola, Rapido ›". Tap it: **Price check · Economy**, with RideVela · Economy first, then **Uber, Ola and Rapido on separate rows** (Uber Go / Ola Mini / Rapido Cab Economy). Rapido is lower than Uber and Ola, and Uber and Ola match. Live reference: us ₹161, Rapido ₹173, Uber ₹201, Ola ₹201 |
| P2 | Tap **Comfort**, then **XL**, then **Premium** | The savings line and the card **switch immediately** to that segment: Comfort → Uber Premier / Ola Prime Sedan / Rapido Cab Premium; XL → Uber XL / Ola Prime SUV / Rapido Cab XL; Premium → Uber Black only. Numbers rise by segment (reference XL: us ₹290, Rapido ₹345, Uber/Ola ₹403) |
| P3 | Pull the sheet up | "Price check · <segment>" is the first section and matches the selected segment |
| P4 | Book between 00:00 and 05:00 IST (optional) | Competitor prices include the 25% night charge |

How competitor prices are modelled (backend/src/comparison/competitor-config.ts, sources in its comments):
- the Pune RTA app-cab rate is ₹25/km, with a ₹75 minimum covering the first 3 km;
- Uber and Ola add a 5% convenience fee;
- Rapido is about 10% lower (zero-commission model);
- surge is capped at 1.5x and discounts at 25%;
- segment ratios are Comfort 1.375x, XL 2x, Premium 2.5x.

All competitor prices are estimates, and the card says so.

## 4. Driver app

```sh
cd ~/ubernav/apps/driver_app && flutter pub get && (cd ios && pod install)
flutter run --release -d $SIM --dart-define=API_BASE_URL=$URL \
  --dart-define=MARKET=in --dart-define=ALLOW_SERVER_OVERRIDE=true \
  --build-name=2.15.0 --build-number=7500
```
| # | SHOW |
|---|---|
| D1 | Offline sheet: "You're offline", earned today, **fatigue bar** ("Online today: Xm of 12h"), **Quests** card with progress, Go online |
| D2 | **Drag the offline/online sheet up** (new: it was not draggable before): Today tiles (earned, trips, online time, per trip), Busy areas nearby, **Your rates** (acceptance / cancellation), **Tips for drivers** poster carousel, Help |
| D3 | Go online: radar animation, busy areas shaded, **Destination** button (go-home mode: pick Home / search / map; max 2 per day; only offers trips that end closer to home) |
| D4 | Accept an offer → going to pickup / waiting / on trip. **Drag up**: rider card with **★ rating**, route timeline, trip length / progress, fare + **"Collect cash at drop-off"** for cash rides, tools (Safety & SOS, Share, Message, Navigate), driver tip poster |
| D5 | Complete the trip | Trip complete + money animation; **"Rate your rider" stars + Done are always visible, pinned at the bottom**. Drag up: this trip, today's total, quests (quest done → **trophy animation**) |
| D6 | Earnings dashboard (Account / Earnings) | Daily and weekly figures in whole rupees |

## 4b. New in 2.14.0 (driver app fixes from the Android audit)

| # | SHOW |
|---|---|
| F1 | Offline sheet: the fatigue bar at "0m of 12h" is an empty light track, not solid black |
| F2 | Quests card: an active quest says "ends midnight"; an ended one reads "Ended · x of y trips" and is faded; the sheet prefers an active quest |
| F3 | Pull up the online sheet: "Busy areas nearby" lists only hotspots within 5 km, otherwise "No hotspots right now". The driver tip posters' text reads fully (no "…") |
| F4 | Account: the stats row (Rating "New" · Trips · 7 days · plate) is aligned, and each label fits on one line |
| F5 | Earnings: every bar in the 7-day chart has its ₹ amount above it; zero days show a small grey tick |
| F6 | Payouts: a negative balance shows as "−₹35.60" in red, with "You owe commission on cash trips. It's deducted from your next payout." |
| F7 | Vehicle dialog: the "Economy" type text is the same size as the other fields |

## 5. Install on the iPhone

Build the same two apps (sections 2 and 4) on the cabled iPhone with
`--build-name=2.15.0 --build-number=7500`. No THEME flag, no bundle-ID changes.

## 6. Report back

Commit only notes. For each step, write ✅ or ❌ plus the screenshot name into
`docs/ios-ui-tour-<date>.md`. `git add` just that file, commit
"docs: iOS UI tour results" and push. Anything that differs from the SHOW
column is a finding: describe it, don't fix it on the Mac.

**Known open items (not bugs):**
- Terms and Privacy are Draft pages.
- LottieFiles animation licences are not yet confirmed (see
  `packages/design_system/assets/lottie/CREDITS.md`).
- The "share your ride" poster shows a person (Unsplash, no model release).
- Ride-tier photos are recognisable real car models (trade-dress question
  open).
- Driver photos aren't uploaded yet (letter avatar).
- Pickup addresses in the pilot data are Pune; that is test data, not
  marketing copy.
