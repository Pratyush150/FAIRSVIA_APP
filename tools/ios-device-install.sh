#!/bin/bash
# Build the rider and driver apps for a physical iPhone and install them.
#
# Prerequisites (one-time, done by a person):
#   1. Xcode → Settings → Accounts → sign in with an Apple ID.
#   2. Plug the phone in, unlock it, tap "Trust" on the phone.
#   3. Find the team id: Xcode → Settings → Accounts → select the Apple ID →
#      the team row shows a 10-character id (free personal teams work).
#
# Usage:
#   TEAM_ID=ABCDE12345 tools/ios-device-install.sh [rider|driver|both]
# Optional:
#   API_BASE_URL   defaults to this Mac's LAN address on port 3000
#   DEVICE_UDID    defaults to the first connected iPhone
#
# The phone must be on the same Wi-Fi as this Mac, and the backend must be
# running here (`npm run start:dev` in backend/).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHICH="${1:-both}"
: "${TEAM_ID:?Set TEAM_ID to your Apple developer team id (see comments above)}"
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1)"
API_BASE_URL="${API_BASE_URL:-http://${LAN_IP}:3000/api/v1}"
DEVICE_UDID="${DEVICE_UDID:-$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ {print $(NF-3)}' | head -1)}"
[ -n "$DEVICE_UDID" ] || { echo "No connected iPhone found (xcrun devicectl list devices)"; exit 1; }
echo "team=$TEAM_ID device=$DEVICE_UDID api=$API_BASE_URL"
curl -sf -m 5 "$API_BASE_URL/health" >/dev/null || { echo "Backend not reachable at $API_BASE_URL"; exit 1; }

build_and_install() {
  local app="$1" bundle="$2"
  echo "== $app"
  (cd "$ROOT/apps/$app" && flutter build ios --release --no-codesign \
      --dart-define=API_BASE_URL="$API_BASE_URL")
  # Sign + archive with xcodebuild using automatic signing for the team.
  (cd "$ROOT/apps/$app/ios" && xcodebuild -workspace Runner.xcworkspace -scheme Runner \
      -configuration Release -destination "id=$DEVICE_UDID" \
      -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
      -derivedDataPath build/device build | grep -E "error:|BUILD (SUCCEEDED|FAILED)")
  local product="$ROOT/apps/$app/ios/build/device/Build/Products/Release-iphoneos/Runner.app"
  xcrun devicectl device install app --device "$DEVICE_UDID" "$product"
  xcrun devicectl device process launch --device "$DEVICE_UDID" "$bundle" || true
}

case "$WHICH" in
  rider)  build_and_install rider_app  in.novarobotics.ubernav.riderApp ;;
  driver) build_and_install driver_app in.novarobotics.ubernav.driverApp ;;
  both)   build_and_install rider_app  in.novarobotics.ubernav.riderApp
          build_and_install driver_app in.novarobotics.ubernav.driverApp ;;
  *) echo "usage: $0 [rider|driver|both]"; exit 1 ;;
esac
echo "Installed. First launch on the phone: Settings → General → VPN & Device Management → trust the developer profile if iOS asks."
