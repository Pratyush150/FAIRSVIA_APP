# Mac: show the owner every screen, one by one (2026-09-24)

**Who this is for:** the Claude session (or person) on the Mac at
`/Users/parthbhimani/ubernav`. Follow it top to bottom. At every **SHOW** step,
stop, tell the owner what they're looking at and what to check, save a
screenshot, and wait for "next" before moving on.

Rules: never commit `ios/Flutter/Secrets.xcconfig`; never force-push; this Mac
only builds iOS — the backend and the fake drivers run on **nova-pc**
(`ssh nova-pc`, already set up here).

---

## 1. Get the latest code and the server address

```sh
cd ~/ubernav && git pull --ff-only
URL=$(ssh nova-pc 'docker logs ridevela_tunnel 2>&1 | grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" | tail -1')/api/v1
curl -s "$URL/health"        # must print {"status":"ok",...}
mkdir -p ~/Desktop/ridevela-ui
```
Use the **https tunnel** URL, not the Tailscale `http://` one (iOS blocks
plain http in release builds).

## 2. Build and start the rider app

Simulator is fine for showing the UI (fastest); use the cabled iPhone if the
owner wants it in hand (`flutter devices` for its id).

```sh
open -a Simulator            # an iPhone 16/17 simulator
SIM=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
xcrun simctl location $SIM set 18.5204,73.8567          # Pune
cd ~/ubernav/apps/rider_app && flutter pub get && (cd ios && pod install)
flutter run --release -d $SIM \
  --dart-define=API_BASE_URL=$URL --dart-define=MARKET=in \
  --dart-define=ALLOW_SERVER_OVERRIDE=true \
  --build-name=1.5.2 --build-number=5015
```
(Release on a simulator not supported by your Flutter? use `--profile`.)
Screenshot command for every SHOW step:
`xcrun simctl io $SIM screenshot ~/Desktop/ridevela-ui/<theme>/<NN-name>.png`

## 3. The tour (default "Samarkand Turquoise" theme)

Start the helpers **on nova-pc** from a second terminal when a step says so.
`F=~/ubernav/tools/fake-driver-simulator; P='START_LAT=18.5300 START_LNG=73.8475'`

| # | Do | SHOW — what the owner should see |
|---|---|---|
| 01 | App opens | Splash: Road-V mark + "RideVela", a bar filling, gone in ≤1.5 s |
| 02 | Sign in screen | 64 px mark top-left; phone field starts with an **"IN +91" chip**, hint "98765 43210"; "Terms" and "Privacy Policy" are underlined links (tap one: a *Draft* page — no public URL yet) |
| 03 | Type any 10-digit number (e.g. 98765 11111) → Continue | Code screen; the code is shown on screen as **"Dev code: 123456"** — type it |
| 04 | Name → Continue, allow location | Home: map on Pune, "Where to?" |
| 05 | Account menu → Appearance | Light / Dark / Same as phone — flip to Dark and back: the whole app recolours instantly |
| 06 | Where to? → type "Shivajinagar" → "Shivajinagar District Court" | Choose a ride: silver 3/4-view cars; rows say **"Pickup in N min · Drop 4:38 PM"**; an **ⓘ** per row (tap → itemised fare that adds up); **Cash / Add card right above Confirm**; prices in whole rupees; tiers with no car nearby are dimmed and say so |
| 07 | nova-pc: `ssh nova-pc "cd $F && $P node idle-driver.mjs 3"` then Confirm | **Finding your driver**: rings spreading from the pickup on the map; sheet "Economy · ₹75 · Cash", "To Shivajinagar District Court" |
| 08 | Wait 45 s | "**Still looking…** Drivers nearby are busy." |
| 09 | Cancel ride → a reason | Back home |
| 10 | nova-pc: `ssh nova-pc "cd $F && $P APPROACH_S=240 WAIT_AT_PICKUP_S=120 node slow-ride.mjs 3"` then book the same ride | **Driver on the way**: headline "**Priya arriving in N min**" / "Meet at your pickup spot"; card: the **number plate is the biggest text** (MH 12 AB 1234), car below, name + ★ rating; **Ride PIN in four boxes**; grey **Safety** pill; Message button |
| 11 | Tap **Safety** | Call buttons **112 / Police 100 / Ambulance 108**, Send SOS alert, Share trip status (don't press SOS) |
| 12 | Wait for arrival | "Priya has arrived", "I'm on my way" button |
| 13 | Trip starts | In-trip: "**On the way to** Shivajinagar…" shown once; **Safety + Share** pills; ETA line; under 500 m "**Arriving soon**" and Add a stop disappears |
| 14 | Stop slow-ride (Ctrl-C); for a finished ride run `ssh nova-pc "cd $F && $P node demo-live-ride.mjs"` and book again (≈90 s) | **Ride completed**: big check, **one "Total ₹75" line with Details ⌄** (tap: breakdown), "Pay ₹75 in cash", stars, Add to favourites, tips **₹20 / ₹50 / ₹100 / Custom**, **Done pinned at the bottom** |
| 15 | Pickup text anywhere | Landmark/road first: "Mote Mangal Karyalay Road, Dattwadi, Pune" — never "204, …, Maharashtra 411002, India" |

If slow-ride leaves a trip open: `ssh nova-pc "docker exec ubernav_postgres psql -U ubernav -d ubernav -c \"UPDATE trips SET status='cancelled' WHERE status='in_progress' AND updated_at < now() - interval '30 minutes'\""` — only if the owner agrees; it touches shared data.

## 4. Driver app

```sh
cd ~/ubernav/apps/driver_app && flutter pub get && (cd ios && pod install)
flutter run --release -d $SIM --dart-define=API_BASE_URL=$URL \
  --dart-define=MARKET=in --dart-define=ALLOW_SERVER_OVERRIDE=true \
  --build-name=1.5.2 --build-number=5015
```
| # | SHOW |
|---|---|
| D1 | Splash and sign-in carry a small **"Driver" pill** next to the mark |
| D2 | After sign-in: "**Allow location to get ride offers**" explainer *before* the iOS prompt; choose "Don't Allow" once → banner with **Open Settings** |
| D3 | Account: profile card with rating ("New"), trips (last 7 days), plate; phone shown spaced "+91 98765 11111" |

## 5. The three looks for the owner to choose between

Same tour (steps 01, 06, 10, 11, 14 are enough), rebuilt with one extra flag
each. **On iOS they replace each other** (same bundle ID) — build, show,
screenshot into `~/Desktop/ridevela-ui/<theme>/`, then the next.

| Theme flag | Plan | What's different |
|---|---|---|
| *(none)* | Samarkand Turquoise (current) | White/black, teal-navy buttons, silver cars |
| `--dart-define=THEME=midnight` | **A — Midnight Teal** | Dark by default (#0E0F11), bright teal #2BC4C4 buttons, flat silver cars with a teal stripe, rounder corners |
| `--dart-define=THEME=daylight` | **B — Daylight 3D** | Light grey page, white sheets, deep teal #0A7C7C buttons, **3D cars** (teal/slate/sand/graphite), 3D Add-a-stop / Pre-book / check / cash icons |
| `--dart-define=THEME=daynight` | **C — Day & Night** | B by day, A by night (follows the phone); the theme **doesn't switch mid-ride** — test: start a ride, switch the simulator to Dark (Settings → Developer → Dark Appearance, or `xcrun simctl ui $SIM appearance dark`), the app stays light until the ride ends |

**More options (added 2026-09-24, same tour, one flag each):**

| Theme flag | Option | Look |
|---|---|---|
| `THEME=local` | **D — Local Colour** | Warm paper #FBF7F0, deep teal #0A6E6E buttons |
| `THEME=ink` | **E — Ink & Paper** | Near-black ink buttons on paper #FAFAF7; teal only for the route/selection |
| `THEME=glass` | **F — Map Glass** (solid fallback) | Cool grey sheets, teal #007A7A. **The frosted-glass sheets are not built yet** — this shows F's colours only |
| `THEME=indigo` | Palette **Ikat Indigo** (top pick) | Indigo #4B32C3 buttons, violet route |
| `THEME=lapis` | Palette **Registan Lapis & Gold** | Lapis blue #1D3F9E; gold route in dark mode |
| `THEME=marigold` | Palette **Marigold** | Burnt orange #B8430A |
| `THEME=copper` | Palette **Bukhara Copper** | Graphite buttons, copper route |
| `THEME=garnet` | Palette **Anor Garnet** | Pomegranate #9B1B45 |

Layout and copy are identical in every option; only tokens change. The car
art in these is still the silver/teal-stripe set.

On Android the owner already has these as separate apps ("RideVela A ·
Midnight", "B · Daylight", "C · Day&Night") — the APKs are on nova-pc in
`~/ubernav/build-variants/`.

## 6. Report back

Commit nothing but notes. Write what you saw per step (✅ / ❌ + screenshot
name) into `docs/ios-ui-tour-<date>.md`, `git add` just that file, commit
"docs: iOS UI tour results" and push. Anything that differs from the SHOW
column is a finding — describe it, don't fix it on the Mac.

**Known placeholders (not bugs):** Terms/Privacy are Draft pages; the 3D icons
in B/C are stand-ins (Microsoft Fluent 3D, MIT) until commissioned art; Android
SMS auto-read is not built; driver photos aren't uploaded yet (letter avatar).
