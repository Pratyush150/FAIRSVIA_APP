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
  --build-name=1.8.0 --build-number=5040
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
  --build-name=1.8.0 --build-number=5040
```
| # | SHOW |
|---|---|
| D1 | Splash and sign-in carry a small **"Driver" pill** next to the mark |
| D2 | After sign-in: "**Allow location to get ride offers**" explainer *before* the iOS prompt; choose "Don't Allow" once → banner with **Open Settings** |
| D3 | Account: profile card with rating ("New"), trips (last 7 days), plate; phone shown spaced "+91 98765 11111" |

## 5. The shortlist (owner, 2026-09-25): four looks only

Build and show **only these four**. The other `THEME=` flags in the code
(midnight, daylight, local, ink, indigo, lapis, marigold, copper, garnet) are
off the shortlist — do not build or show them.

| Theme flag | Look | What to point out |
|---|---|---|
| *(none)* | **Samarkand Turquoise** (current) | Clean white/black, teal buttons, 3D cars in the list and on the map |
| `--dart-define=THEME=daynight` | **C — Day & Night** | Light by day, dark by night (follows the phone); the theme **doesn't switch mid-ride** — test: start a ride, `xcrun simctl ui $SIM appearance dark`, it stays light until the ride ends |
| `--dart-define=THEME=glass` | **F — Map Glass** | Floating **frosted** "Where to?" pill, compact ride card over the map, **plate tag under the car on the map**, glossy icon beads. Check the blur is smooth |
| `--dart-define=THEME=clay3d` | **G — 3D Clay** | **Every icon is a 3D clay image**, coloured by meaning; one icon set for light and dark. Icons come from a colour bitmap font (sbix for iOS) — **check they show in colour on the iPhone**; blank boxes = sbix not used |

Auto and Bike ride types are switched off — don't show them.

## 5b. Put the four shortlisted looks on the owner's iPhone (the "IPAs")

iOS gives every build the same bundle ID, so by default each look replaces
the last. To have **all four side by side on the iPhone** (as on Android),
give each its own bundle ID and name — only in your local build, don't
commit the Xcode change:

```sh
cd ~/ubernav/apps/rider_app
for pair in ":RideVela" "daynight:RideVela C" "glass:RideVela F" "clay3d:RideVela G"; do
  t=${pair%%:*}; name=${pair#*:}
  SUF=${t:+.$t}
  flutter build ios --release \
    --dart-define=API_BASE_URL=$URL --dart-define=MARKET=in \
    --dart-define=ALLOW_SERVER_OVERRIDE=true ${t:+--dart-define=THEME=$t} \
    --build-name=1.8.0 --build-number=5040
  # per-look bundle id + name, then install on the cabled iPhone
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier in.novarobotics.ubernav.rider$SUF" build/ios/iphoneos/Runner.app/Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $name" build/ios/iphoneos/Runner.app/Info.plist
  codesign --force --sign "Apple Development" --entitlements ios/Runner/Runner.entitlements build/ios/iphoneos/Runner.app 2>/dev/null \
    || codesign --force --sign "Apple Development" build/ios/iphoneos/Runner.app
  xcrun devicectl device install app --device <iphone-udid> build/ios/iphoneos/Runner.app
done
```
If re-signing after changing the bundle ID fails (free Apple ID: each new
bundle ID needs its own provisioning profile), instead set the bundle ID in
Xcode (Runner → Signing & Capabilities) per look and `flutter run --release`
each one — slower but reliable. Free-account installs expire after 7 days.
Also install the driver app (section 4) once.

**What's new in 1.7.0 to point out:** real 3D cars in the ride list (the
current look, B and C; A keeps flat silver cars), the booked car shown
top-down on the map and turning with the road, the driver card shows the
driver over their 3D car, and a new auto-rickshaw icon.

## 6. Report back

Commit nothing but notes. Write what you saw per step (✅ / ❌ + screenshot
name) into `docs/ios-ui-tour-<date>.md`, `git add` just that file, commit
"docs: iOS UI tour results" and push. Anything that differs from the SHOW
column is a finding — describe it, don't fix it on the Mac.

**Known placeholders (not bugs):** Terms/Privacy are Draft pages; the 3D icons
in B/C are stand-ins (Microsoft Fluent 3D, MIT) until commissioned art; Android
SMS auto-read is not built; driver photos aren't uploaded yet (letter avatar).
