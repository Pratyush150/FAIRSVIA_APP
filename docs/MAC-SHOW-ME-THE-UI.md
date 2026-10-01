# Mac: show the owner every FAIRSVIA screen, one by one (written 2026-10-01, v1.0.0)

**Who this is for:** the Claude session (or person) on the Mac. Follow it top
to bottom. At every **SHOW** step, stop, tell the owner what they're looking at
and what to check, save a screenshot, and wait for "next" before moving on.

**How it should look (different from RideVela on purpose):** Ocean Blue
accent with coral highlights (no teal anywhere), UI text in the rounder **Anek
Latin** face (fares and plates stay Inter), rounder cards and sheets, and
**pill-shaped** main buttons. The animated icons (bottom bar, Offers gift, ticks,
loaders) and the Home tile pictures are blue/coral; trophy and coins stay gold.
Report any leftover teal as a finding.

**What FAIRSVIA is:** a separate product built from the RideVela codebase. It is
the same app with **no price comparison anywhere**: no "Save ₹X vs …" line, no
Price check card, no competitor prices, no price match. Fares come only from
FAIRSVIA's own rate card. It has its own name, its own "Road-F" icon, its own
**Ocean Blue** accent (RideVela is teal), and its own app IDs, so both apps can
be installed on the same iPhone side by side.

Rules: never commit `ios/Flutter/Secrets.xcconfig`. Never force-push. Never
touch the RideVela checkout (`~/ubernav`) or its containers. This Mac only
builds iOS. The FAIRSVIA backend and the fake drivers run on **nova-pc**
(`ssh nova-pc`). **Nothing here has been run on iOS yet.** Android 1.0.0 was
checked on nova-pc's emulator, so treat every row as "expected", not "already
seen on an iPhone".

| | FAIRSVIA | (RideVela, for reference: don't touch) |
|---|---|---|
| Repo | `https://github.com/Pratyush150/FAIRSVIA_APP` → `~/FAIRSVIA_APP` | `~/ubernav` |
| Rider bundle ID | `in.novarobotics.fairsvia.rider` | `in.novarobotics.ubernav.riderApp` |
| Driver bundle ID | `in.novarobotics.fairsvia.driver` | `in.novarobotics.ubernav.driverApp` |
| Home-screen names | FAIRSVIA Rider / FAIRSVIA Driver | RideVela Rider / RideVela Driver |
| URL schemes | `fairsviaapp-rider://`, `fairsviaapp-driver://` | `fairsvia-rider://`, `fairsvia-driver://` |
| Backend on nova-pc | container `fairsvia_backend`, host port **3200** | `ubernav_backend`, 3000 |
| Public tunnel | container `fairsvia_tunnel` | `ridevela_tunnel` |

---

## 1. Get the code, the Maps key and the server address

```sh
git clone https://github.com/Pratyush150/FAIRSVIA_APP ~/FAIRSVIA_APP   # first time only
cd ~/FAIRSVIA_APP && git pull --ff-only
# Google Maps iOS key: gitignored, one file per app. Ask the owner for the
# FAIRSVIA key. It is not the RideVela key, because keys are restricted per bundle ID.
for a in rider_app driver_app; do
  printf 'MAPS_API_KEY=<FAIRSVIA iOS key>\n' > apps/$a/ios/Flutter/Secrets.xcconfig
done
URL=$(ssh nova-pc 'docker logs fairsvia_tunnel 2>&1 | grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" | tail -1')/api/v1
curl -s "$URL/health"        # must print {"status":"ok",...}
mkdir -p ~/Desktop/fairsvia-ui
```
Without the Maps key the map renders **blank grey with no error**. Use the
**https tunnel** URL, because iOS blocks plain http in release builds. The
quick-tunnel URL changes whenever nova-pc's internet drops. If `/health` fails,
run `ssh nova-pc 'docker restart fairsvia_tunnel'` (**not** `ridevela_tunnel`),
wait 10 s, and fetch the URL again.

## 2. Build and start the rider app

```sh
open -a Simulator            # an iPhone 16/17 simulator
SIM=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl location $SIM set 18.5204,73.8567          # pilot area (Pune)
cd ~/FAIRSVIA_APP/apps/rider_app && flutter pub get && (cd ios && pod install)
flutter run --release -d $SIM \
  --dart-define=API_BASE_URL=$URL --dart-define=MARKET=in \
  --dart-define=ALLOW_SERVER_OVERRIDE=true \
  --build-name=1.0.0 --build-number=1
```
If release mode isn't supported on the simulator, use `--profile`. For a
cabled iPhone, use its id from `flutter devices`. No THEME flag: the default
build is the shipped look.

Screenshot for every SHOW step:
`xcrun simctl io $SIM screenshot ~/Desktop/fairsvia-ui/<NN-name>.png`

## 3. Rider tour

On **nova-pc**, run helpers from a second terminal when a step says so. The
simulator scripts already default to the FAIRSVIA backend (`localhost:3200`):
`F=~/fairsvia_app/tools/fake-driver-simulator; P='START_LAT=18.5300 START_LNG=73.8475'`

| # | Do | SHOW: what the owner should see |
|---|---|---|
| 01 | App opens | Splash: the **FAIRSVIA** wordmark with the blue **Road-F** mark, and a car gliding along a road line. Gone in ≤1.8 s |
| 02 | Sign in: any 10-digit number → Continue → type the **"Dev code: 123456"** shown on screen → name → allow location | Home |
| 03 | Home | Floating frosted **"Where to?"** bar with a **blue→cyan→violet ring that keeps turning** and a soft glow. The leading icon is an animated location pin. "Later ⌄" is on the right |
| 04 | Scroll Home | Recent places, then the **Ride / Pre-book / For others / Saved places** tiles, a swipeable poster strip (dots, shimmer every ~6 s), and promo banners. Selected and accent items are **Ocean Blue**, not teal |
| 05 | Press and hold a tile or poster | It shrinks slightly and glows |
| 06 | Bottom nav → **Offers** | Animated gift icon. Real codes: WELCOME50, AIRPORT100, WEEKEND20 |
| 07 | Account → Appearance | Light / Dark / Same as phone. It recolours instantly at any time, including mid-ride, without resetting the ride. In dark mode buttons are bright blue |
| 08 | Where to? → type a place | Each result shows its distance under the pin. Type nonsense to get an animated "No places found" |
| 09 | Pick "Shivajinagar District Court" | **Choose a ride**: Economy, Comfort, XL and Premium, with whole white cars. Picking one plays an animated tick. Cash / Card sits above Confirm. **There is no "Save ₹X vs …" line and no competitor name anywhere** |
| 10 | Drag the Choose-ride sheet fully up | Ride now / Schedule, promo code, **About this fare** (distance, minutes, surge line), **Safety on every ride** tiles, posters. **No "Price check" section and no "Compare rides" section** |
| 11 | Tap the fare "ⓘ" | Base, distance, time, booking fee (and surge/promo when they apply). **No "price match" line** |
| 12 | "Later ⌄" | **Pre-book** with a 12-hour clock (AM/PM) and Cash / Card chips. It books and confirms |
| 13 | nova-pc: `ssh nova-pc "cd $F && $P node idle-driver.mjs 3"`, then Confirm | **Finding your driver**: radar rings on the map. The search runs for up to 3 min |
| 14 | Cancel. Then nova-pc: `ssh nova-pc "cd $F && $P APPROACH_S=240 WAIT_AT_PICKUP_S=120 node slow-ride.mjs 3"` and book again | **Driver on the way**: plate biggest, car, name + ★, Ride PIN, Call + Message. Pulled up: car gliding toward the pickup pin, "At your pickup by h:mm AM/PM", the SOS tile pulses red |
| 15 | Driver arrives | "has arrived" with an arrived animation |
| 16 | Trip starts | "On the way to …". Pulled up: **Trip progress** with a car sliding along the bar, and trip details (Pickup, Ride, Promo, Pay by, Fare in bold, values right-aligned) |
| 17 | For a finished ride: `ssh nova-pc "cd $F && $P node demo-live-ride.mjs"`, then book | **Ride completed**: confetti, "Total ₹…" with Details, stars, tips, Done pinned |
| 18 | Trips tab → tap a past trip → Receipt | Route snapshot, fare breakdown and payment. **No "FAIRSVIA price match" line** |
| 19 | Map anywhere | Solid pins and a blue location dot with a halo. The Google logo is visible bottom-left above the sheet |
| 20 | Back from any tab | Goes to Home first. Back on Home leaves the app. Back during a live ride never cancels it |
| 21 | Account → Credits & licences | Flutter licence page titled FAIRSVIA |

## 4. Driver app

```sh
cd ~/FAIRSVIA_APP/apps/driver_app && flutter pub get && (cd ios && pod install)
flutter run --release -d $SIM --dart-define=API_BASE_URL=$URL \
  --dart-define=MARKET=in --dart-define=ALLOW_SERVER_OVERRIDE=true \
  --build-name=1.0.0 --build-number=1
```
| # | SHOW |
|---|---|
| D1 | Location priming screen says "FAIRSVIA needs your location…", with the navy Road-F mark |
| D2 | Offline sheet: "You're offline", earned today, fatigue bar, Quests card, Go online |
| D3 | Drag the sheet up: Today tiles, Busy areas nearby, Your rates, Tips for drivers carousel, Help |
| D4 | Go online: radar animation, busy areas shaded, Destination button |
| D5 | Accept an offer → going to pickup / waiting / on trip. Drag up: rider card, route timeline, fare, "Collect cash at drop-off" for cash rides |
| D6 | Complete the trip: money animation; "Rate your rider" stars + Done pinned at the bottom |
| D7 | Earnings: daily and weekly figures in whole rupees |

## 5. Install on the iPhone next to RideVela

Build both apps (sections 2 and 4) on the cabled iPhone with
`--build-name=1.0.0 --build-number=1`. Don't add a THEME flag and don't change
the bundle IDs. Signing needs a team that can register
`in.novarobotics.fairsvia.rider` / `.driver`. **Check:** the home screen shows
FAIRSVIA Rider and FAIRSVIA Driver (blue F icons) **next to** RideVela Rider and
RideVela Driver (teal V icons), and both pairs open and work independently.

## 6. Report back

Commit only notes. For each step, write ✅ or ❌ plus the screenshot name into
`docs/ios-ui-tour-<date>.md`. `git add` just that file, commit
"docs: iOS UI tour results" and push to FAIRSVIA_APP. Anything that differs
from the SHOW column is a finding: describe it, don't fix it on the Mac.

**Known open items (not bugs):**
- Payments run on the mock provider until FAIRSVIA has its own Stripe keys.
- Terms and Privacy are draft pages. Lottie licences are not yet confirmed.
