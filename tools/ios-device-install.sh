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
#   API_BASE_URL   defaults to the live backend (https://rideapp.fairsvia.com/api/v1),
#                  which works over mobile data; set it to http://<mac-lan-ip>:3000/api/v1
#                  to test against a backend running on this Mac (same Wi-Fi only)
#   DEVICE_UDID    defaults to the first connected iPhone
#
# The phone needs Developer Mode on (Settings > Privacy & Security > Developer
# Mode, then restart) before a development build can be installed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHICH="${1:-both}"
: "${TEAM_ID:?Set TEAM_ID to your Apple developer team id (see comments above)}"
API_BASE_URL="${API_BASE_URL:-https://rideapp.fairsvia.com/api/v1}"
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
  rider)  build_and_install rider_app  in.novarobotics.fairsvia.rider ;;
  driver) build_and_install driver_app in.novarobotics.fairsvia.driver ;;
  both)   build_and_install rider_app  in.novarobotics.fairsvia.rider
          build_and_install driver_app in.novarobotics.fairsvia.driver ;;
  *) echo "usage: $0 [rider|driver|both]"; exit 1 ;;
esac
echo "Installed. First launch on the phone: Settings → General → VPN & Device Management → trust the developer profile if iOS asks."
