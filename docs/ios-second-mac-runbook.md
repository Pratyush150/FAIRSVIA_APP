# Second Mac + second iPhone: prompt and runbook

Copy the block below into Claude Code (or hand it to a person) on the other
Mac. It reproduces what was done on the first Mac on 2026-09-15 and avoids the
traps we hit. Two phones are needed for a real ride: one runs the rider app,
the other the driver app. Each Mac only needs its own phone.

---

## Prompt for Claude Code on the second Mac

```
Set up this Mac to build the FairsVia iOS apps from the GitHub repo
Pratyush150/ubernav and install them on the iPhone that is plugged in.
Work autonomously, be strictly honest, never claim a step worked without
evidence, and tell me exactly which steps need a human click.

Repo and branch
- Clone https://github.com/Pratyush150/ubernav.git into ~/ubernav using the
  GitHub token I give you, passing it only as an HTTP header
  (git -c http.extraheader="Authorization: Basic $(printf 'x-access-token:TOKEN' | base64)"),
  never storing it in the remote URL. Check out branch feat/map-eta-and-audit-fixes.
- Read CLAUDE.md, docs/ios-mac-setup.md and docs/ios-second-mac-runbook.md first.

Toolchain (verify each, install what is missing)
- Xcode from the App Store (26.x), then:
    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
    sudo xcodebuild -license accept
- Homebrew, then: brew install cocoapods libimobiledevice
- Flutter 3.44.x on PATH; `flutter doctor` must show Xcode green.
- iOS simulator runtime is NOT needed for a phone install.

Secrets (gitignored, never commit or print them)
- Create apps/rider_app/ios/Flutter/Secrets.xcconfig and
  apps/driver_app/ios/Flutter/Secrets.xcconfig, each one line:
    MAPS_API_KEY=<the Google Maps key I give you>
- The apps talk to the live backend https://rideapp.fairsvia.com/api/v1
  (hands out dev OTP codes, no SMS needed). No backend runs on this Mac.

Dependencies
- cd apps/rider_app && flutter pub get && (cd ios && pod install)
- cd apps/driver_app && flutter pub get && (cd ios && pod install)

Signing (needs my clicks; walk me through them one at a time)
1. Xcode menu bar > Xcode > Settings… > Accounts > + > Apple ID: sign in.
   (It is NOT on the welcome window that shows "Create new project".)
2. If no "Personal Team" appears under the account: sign in once at
   https://developer.apple.com/account with that Apple ID and accept the
   agreement, then remove and re-add the account in Xcode.
3. `open apps/rider_app/ios/Runner.xcworkspace`; in Xcode: blue Runner icon
   > TARGETS Runner > Signing & Capabilities > tick "Automatically manage
   signing" > Team = "<name> (Personal Team)". Read the 10-character team id
   from apps/rider_app/ios/Runner.xcodeproj/project.pbxproj (DEVELOPMENT_TEAM).
   Do not commit that change.
4. Confirm with `security find-identity -v -p codesigning` that an
   "Apple Development" identity exists.

Phone (needs my clicks)
1. Data-capable cable straight into the Mac (no hub). Phone unlocked. Tap
   Trust. Verify with `idevice_id -l` and
   `xcrun devicectl device info details --device <udid>` (tunnelState connected).
2. Developer Mode: run `idevicedevmodectl reveal` to make the switch appear,
   then I turn it on under Settings > Privacy & Security > Developer Mode
   (phone restarts, tap Turn On). Verify `idevicedevmodectl list` says enabled.
   Apple cannot issue a free-team provisioning profile until the phone is
   registered, and registration needs Developer Mode on.

Build + install (script exists: tools/ios-device-install.sh)
- Keep at least 15 GB free on disk before building (a full build of both apps
  used ~10 GB and a full disk corrupts the build database).
- TEAM_ID=<team id> tools/ios-device-install.sh both
  (it runs flutter build ios --release --no-codesign, then xcodebuild with
   -destination "id=<udid>" -allowProvisioningUpdates
   -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=... , then
   xcrun devicectl device install app).
- If xcodebuild fails with errSecInternalComponent while codesigning: macOS is
  refusing the signing key to a background process. Run one direct
  `codesign --force --sign <identity-hash> <any built binary>` so the keychain
  dialog appears, click "Always Allow", then rerun the script.
- If xcodebuild says "Your team has no devices": the phone was not usable
  (Developer Mode off or locked). Fix that and rerun with the phone as the
  destination; never use generic/platform=iOS for a free team's first build.
- On the phone, first launch may ask: Settings > General > VPN & Device
  Management > trust the developer app.

Report
- Give me: which of rider/driver installed (bundle ids
  in.novarobotics.ubernav.riderApp / in.novarobotics.ubernav.driverApp), the
  exact commands that ran, any error text verbatim, and what still needs me.
```

---

## What each Mac needs from the owner

| Item | Where it goes | Notes |
|---|---|---|
| GitHub token | header only, never in the URL | rotate it after the test |
| Google Maps key | the two gitignored Secrets.xcconfig files | key must have Maps SDK for iOS enabled (it does; the map rendered on iOS here) |
| Apple ID | Xcode > Settings > Accounts | free account is enough; installs expire after 7 days, rerun the script to refresh |
| Phone with Developer Mode on | plugged in, unlocked | `idevicedevmodectl reveal` makes the switch appear |

## Field test, two phones

- Phone A (rider) and phone B (driver) both on mobile data; both sign in with
  any phone number, the code is shown on screen ("Dev code" chip).
- Driver: onboard a vehicle when asked, then Go online. Rider: set a
  destination a few hundred metres away, confirm. The driver phone should
  ring with the offer within a few seconds.
- Watch: map renders (not grey), location prompt and blue dot, offer arrives,
  live car on the rider map, Arrived only within 150 m, start code, route
  shrinking, completion + tip, receipts in Your trips.
- Not wired: push notifications. Keep both apps in the foreground.

## Why parallel agents do not speed this up

Every blocking step is a human click on Apple's side (Apple ID sign-in, team
selection, Trust prompt, Developer Mode, keychain dialog). The builds
themselves take about ten minutes and are best run one after the other on one
Mac to avoid the full-disk failure. Two Macs in parallel is the right
parallelism: one per phone, each following this runbook.
