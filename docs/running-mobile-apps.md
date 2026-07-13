# Running the mobile apps (rider & driver) with Android Studio

The rider and driver apps are native mobile Flutter apps, so they need the Android SDK and an
emulator (or a real phone). The admin app is web-only and just needs Chrome.

## One-time setup

1. **Install Android Studio** — https://developer.android.com/studio
   During first launch, let it install the **Android SDK**, **SDK Platform-Tools**, and an
   **Android SDK Build-Tools** package (the setup wizard does this by default).

2. **Point Flutter at it and accept licenses**:
   ```bash
   export PATH="/home/nova-robotics/flutter/bin:$PATH"
   flutter doctor --android-licenses   # press y to accept all
   flutter doctor                       # should show Android toolchain ✓
   ```

3. **Create an emulator (AVD)**: Android Studio → *More Actions* → *Virtual Device Manager* →
   *Create Device* → pick e.g. **Pixel 7**, a recent system image (API 34/35), Finish.
   (Or skip the emulator and use a **real phone**: enable Developer Options → USB debugging,
   plug in via USB, accept the prompt.)

## Run the apps

Start the backend first (`cd infra && docker compose up -d`), then:

```bash
export PATH="/home/nova-robotics/flutter/bin:$PATH"
cd /home/nova-robotics/ubernav
flutter pub get                       # once, from repo root

# Launch the emulator (or plug in a phone), then:
flutter devices                       # confirm the device is listed

# IMPORTANT: an Android emulator reaches the host machine at 10.0.2.2, NOT localhost.
cd apps/rider_app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1

# In another terminal, the driver app on a second emulator/device:
cd apps/driver_app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```

A **real phone** on the same Wi-Fi uses your computer's LAN IP instead:
`--dart-define=API_BASE_URL=http://<your-computer-ip>:3000/api/v1`.

## Manual test checklist (Phase 0 — login)

1. App opens on the phone entry screen.
2. Type `+919876543210` → **Continue**.
3. OTP screen shows; read the 4-digit code from the on-screen **DEV code** hint
   (also visible in `docker compose logs -f backend`).
4. Enter the code → you land on the app's home screen showing your phone number.
5. Tap **logout** (top-right) → returns to phone entry.
6. Kill and reopen the app → it should reopen already logged in (session restored).

## Notes
- iOS builds additionally require a **Mac + Xcode** — not needed for Android/web development.
- `flutter doctor` is your friend: it tells you exactly what's missing.
