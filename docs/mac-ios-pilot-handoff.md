# START HERE on the Mac — iOS for the Pune pilot (2026-09-23)

This is the one document to follow on the Mac. It says exactly what changed,
how to build the iPhone apps for the pilot, and how to check the iPhone does
**everything the Android build was verified to do** — item by item, with the
exact text you should see. Older Mac docs (`handoff-for-mac.md`,
`ios-mac-setup.md`, `ios-second-mac-runbook.md`) still hold useful setup
detail; where they disagree with this file, **this file wins**.

---

## 1. Where things stand (verified vs not)

| | State |
|---|---|
| **Android** | Pilot APKs **v1.2.0 (build 5002)** — the Uber-style UI — on two real phones (Realme RMX3381, Moto G34) and verified on the emulator **through the public link, placed in Pune**, light and dark mode. |
| **iOS** | **Not built since 2026-09-14.** Cannot be built on the Linux server. Last run was on simulators only — **never on a physical iPhone**. Everything below is what needs proving. |
| **Backend** | Runs in Docker on the Linux box (office). Reached by phones through a **public HTTPS link** (Cloudflare tunnel). |
| **Market** | Pilot is **Pune, India**: rupees (₹), kilometres, +91 phone numbers, Pune fares. (Uzbekistan launch later uses the same switches with `uz`.) |

---

## 2. What changed today that iOS must prove

All of this is Dart (shared by Android and iOS) or backend. **No native iOS
code, Xcode project setting or Info.plist was changed today.** One new native
dependency arrived since the last iOS build: `sentry_flutter` 9.x (error
tracking) — CocoaPods will add the `Sentry` pod on the first build.

| Change | What the rider/driver sees |
|---|---|
| **Market setting** (`--dart-define=MARKET=in`) | Every price in ₹, distances in m/km, tip buttons ₹20/₹50/₹100, phone hint "+91 98765 43210" |
| **Local phone numbers** | "9000000001" typed without +91 is accepted and becomes +919000000001 |
| **Place names** | Destination reads "Pune station, Agarkar Nagar…", never a code like "GVHF+GQF" |
| **Driver earnings** | "Today's earnings" is the driver's share (80% of fare), not the full fare |
| **Card rides need a card** | With no saved card the app books cash (server refuses a card ride with no card) |
| **Server address** (pilot builds only) | Long-press the logo on the sign-in screen → change the server address |
| **Stuck-ride sweeper** (server) | A ride search that is orphaned ends by itself after 10 min instead of hanging |
| Earlier today, already on Android | Driver-arriving screen: ride PIN, "I'm on my way", ••• menu, promo cards, Add a stop, Pre-book; SOS with emergency contacts; account deletion |

---

## 3. Prerequisites on the Mac (one-time)

1. **Xcode** (last used: 26.6) with command-line tools, **CocoaPods**, and
   **Flutter 3.44.x** (same major as the server: `flutter --version`).
2. `git pull` the repo (see §8 — the latest commits must be pushed from the
   Linux box first, or they won't be there).
3. **Google Maps key for iOS** — without it the map is a blank grey grid.
   Create two gitignored files (never commit them):
   ```sh
   for app in rider_app driver_app; do
     echo 'MAPS_API_KEY=<the iOS Maps key>' > apps/$app/ios/Flutter/Secrets.xcconfig
   done
   ```
   The key needs **Maps SDK for iOS** enabled in Google Cloud.
4. **Signing for a physical iPhone:** open `apps/rider_app/ios/Runner.xcworkspace`
   (the *workspace*, not the project) → Runner → Signing & Capabilities →
   choose your **Team**. Repeat for `driver_app`.
   - Bundle IDs: `in.novarobotics.ubernav.riderApp`, `in.novarobotics.ubernav.driverApp`.
     A free Apple ID may force you to change them to something unique — that
     is fine for testing, just don't commit the change.
   - Free Apple ID signing expires after **7 days** and only installs on
     phones plugged into this Mac. To hand an iPhone build to an investor
     or tester remotely you need the paid Apple Developer account (TestFlight).
   - On the iPhone, first launch: Settings → General → VPN & Device
     Management → trust the developer.

---

## 4. Get the current server address (do this every time)

The public link is a Cloudflare **quick tunnel**; its address **changes
whenever the tunnel restarts** (reboot, Docker restart). On the Linux box:

```sh
docker logs ridevela_tunnel 2>&1 | grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | tail -1
```
Today it is `https://interviews-wallace-quality-destination.trycloudflare.com`.
Check it answers: `curl <address>/api/v1/health` → `{"status":"ok",...}`.

If it changed after apps were installed, don't rebuild: on each phone
long-press the logo on the sign-in screen → paste `<address>/api/v1` →
**Check and save** → close and reopen the app.

(The permanent fix is a *named* tunnel on the RideVela Cloudflare account,
e.g. `api.ridevela.com` — needs the owner's one-time `cloudflared tunnel login`.
Then no address ever changes.)

---

## 5. Build and run on the iPhone

Exactly the settings the Android pilot APKs were built with:

```sh
URL=https://<current-tunnel>.trycloudflare.com/api/v1
for app in rider_app driver_app; do
  cd apps/$app
  flutter pub get
  (cd ios && pod install)          # first build after pulling: adds the Sentry pod
  flutter run --release -d <your-iphone-id> \
    --dart-define=API_BASE_URL=$URL \
    --dart-define=MARKET=in \
    --dart-define=ALLOW_SERVER_OVERRIDE=true \
    --build-name=1.2.0 --build-number=5002
  cd ../..
done
```
`flutter devices` lists the iPhone id. `--release` matters: debug builds on a
physical iPhone stop working once disconnected from the Mac.

**If the build fails**, most likely causes, in order: (1) signing team not set;
(2) pods out of date → `cd ios && pod repo update && pod install`;
(3) deployment target — the project and Podfile say iOS 15.0; a pod that
needs higher shows it in the error, raise both to match.

---

## 6. Demo accounts (no SMS provider yet)

Over the public link, a login code is shown on screen **only** for these
numbers (any other number, including the admin's, gets no code — on purpose):

| Riders | Drivers |
|---|---|
| 9000000001, 9000000002, 9000000003 | 9000000011, 9000000012, 9000000013 |

Type them as shown (the app adds +91). The code appears in an orange
"Dev code" pill under the input.

---

## 7. The iPhone checklist — same checks Android passed today

Do these in order. Each line is what Android showed; iOS must match. Mark
anything different in §9 of `remaining-work-plan.md` with a screenshot.

**Rider app**
1. Sign-in screen: hint reads **"+91 98765 43210"**. Type `9000000001` → Continue is enabled.
2. Code screen: "We sent a 6-digit code to **+919000000001**", orange **Dev code** pill. Enter it.
3. Name screen → enter a name → home map shows **your real location in Pune**
   (grant location "While Using the App"). Map tiles load (if grey, the Maps key — §3.3).
4. Search "Pune station": results in **km** (e.g. "2.1 km").
5. Ride options: header **"x.x km · N min"** (never "mi"), fares in **₹**
   (≈ ₹90–₹100 for ~2.5 km economy), no "price comparison" card.
6. Payment is **Cash** (no card saved). Confirm.
7. Driver-arriving screen: **4-digit PIN**, pickup + "Economy" + "Cash" chips,
   driver card with plate, Message, Details, **Add a stop**, **Pre-book**.
8. ••• → Cancel ride: dialog says **"a ₹50 cancellation fee"**. Tap **Keep ride**.
9. In-trip: **"Arriving h:mm · N min · x.x km to go"**; destination reads a
   place name, **not** a "XXXX+XXX" code.
10. Completed: **₹** fare, "Pay ₹… in cash to your driver", tip buttons
    **₹20 / ₹50 / ₹100 / Custom**, no "$" anywhere.
11. Pilot option: long-press the logo on the sign-in screen → "Server address"
    page opens; an http:// address is refused.

**Driver app** (a second phone, or the same phone after the rider ride)
1. Sign in with `9000000011`, name → "You're offline · Earned today · **₹0**".
2. Go online → "Set up your vehicle" (e.g. Maruti / Dzire / White / MH12AB1234) → **Online**.
   Allow location **Always** when asked (iOS asks in two steps).
3. A rider books nearby → offer card: **₹fare**, **"x.x km · N min trip"**,
   **"N min · x.x km to pickup"**, 15-second ring. Accept.
4. "Head to pickup · **N m / x.x km** to pickup" → Navigate opens Google Maps /
   Apple Maps with the route → Arrived.
5. Enter the rider's PIN → Start trip → "On trip · … to dropoff" → Complete trip.
6. "Trip complete · Today's earnings · **₹(80% of fare)**", "Collect ₹fare in cash from the rider".
7. **Background:** lock the phone while online on a trip for a minute → the
   rider still sees the car move (driver declares background location).

**UI (v1.2.0, Uber-style) — must match Android, light AND dark mode**
1. Font is **Inter** everywhere (not the iOS system font). If you see San
   Francisco, the font asset didn't load — check `packages/design_system/fonts/Inter-*.ttf`.
2. Main buttons are **black with white text in light mode, white with black
   text in dark mode** (Settings → Display → Dark to test). Nothing black-on-black.
3. Map is **greyscale** (no blue river / yellow road shields), dark in dark mode;
   route line black (white in dark); pickup = black ring, drop-off = black square.
4. Home: one rounded **"Where to?"** bar with a **"Later"** chip inside.
5. Ride list: no boxes around rows; the selected ride has a **2 px black outline**;
   "Economy 👤4 · 8:02 PM · 4 min away · ₹93.11 · Details".
6. Arriving sheet: headline, driver row, **PIN as one black badge**, grey
   **Message** button, grey "Add a stop" / "Pre-book" tiles.
7. The whole route is visible **above** the ride list (not hidden behind it).

**iOS-specific things Android can't tell us — look for them**
- Notch / Dynamic Island / home bar covering buttons (safe areas).
- Keyboard covering the Continue / Verify / Save buttons.
- The location permission flow and the "Always" upgrade for drivers.
- Navigate hand-off (Google Maps if installed, else Apple Maps).
- Phone call / share sheet from the ••• menu and Safety sheet.

---

## 8. Git and the shared server — rules for the Mac

The phones, the emulator and the Mac all use the **same live server and
database**. Things done from the Mac are visible to everyone testing.

- **Never cancel, delete or reset other people's rides or data** to get a
  clean state (a ride was cancelled from outside as "iOS verification reset"
  on 2026-09-23 while Android was mid-test). Use your own demo account and
  finish or cancel only your own rides from the app.
- Don't touch `backend/`, `infra/` or the server's `.env` from the Mac — the
  server runs on the Linux box. iOS work is `apps/*/ios/` and, if a real bug
  needs it, Dart in `apps/` / `packages/`.
- Git: work on `main`, small commits, message prefix `ios:`; always
  `git pull --rebase origin main` before `git push origin main` (the Linux
  box pushes too). Never force-push. Never commit `Secrets.xcconfig`,
  signing/team changes, or a changed bundle ID.
- A Dart change must keep Android working: run `flutter analyze` and
  `flutter test` in every package you touched before pushing.

## 9. Blockers and owner actions (not code)

| Item | Why | How |
|---|---|---|
| **Push the code** | The Linux box can't push (no GitHub credentials cached; the tool refuses to use a token pasted in chat). 20+ commits are local only; CI hasn't run on them | On the Linux box: `cd ~/ubernav && git push origin main`, sign in when asked. Then `git pull` on the Mac |
| Permanent server address | Quick-tunnel address changes on restart | One-time `cloudflared tunnel login` on the RideVela Cloudflare account; then a named tunnel `api.ridevela.com` |
| TestFlight | Share iPhone builds without a cable | Paid Apple Developer account + App Store Connect app records |
| Real SMS | Real users can't log in (only demo accounts) | SMS provider account — waiting on company GST / mobile number |

---

## 10. What is NOT in this pilot (so nobody promises it)

- Real SMS login for arbitrary numbers (demo accounts only).
- Card payments in the pilot (Stripe is test-mode; cash is the pilot's payment).
- Driver photo and car photo on the arriving screen (initials + car icon for now).
- Uzbek / Russian languages; Uzbekistan map data.
