#!/bin/zsh
# Build AirMouse in Release (JS bundle embedded, no Metro needed) and push it
# to the iPhone over USB or the same WiFi.
#
#   airmouse/tools/deploy-ios.sh            # build + install + launch
#   airmouse/tools/deploy-ios.sh --build    # build only (phone not needed)
#
# Unlock the phone first. First launch needs Trust in Settings > General >
# VPN & Device Management. Free provisioning profile expires after 7 days:
# re-run this script.

set -e

DEVICE_UDID="${DEVICE_UDID:-00008120-000235C610A14932}"   # iPhone "Ghost" (`xcrun devicectl list devices`)
BUNDLE_ID='com.nattakit.airmouse'
SCHEME='AirMouse'
IOS_DIR="${0:A:h}/../app/ios"
DERIVED="$IOS_DIR/build/device"
APP="$DERIVED/Build/Products/Release-iphoneos/$SCHEME.app"

if [[ ! -d "$IOS_DIR/$SCHEME.xcworkspace" ]]; then
  echo "No $SCHEME.xcworkspace: run 'npx expo prebuild --platform ios --no-clean' in app/ first." >&2
  exit 1
fi

echo '==> Building (Release)…'
cd "$IOS_DIR"
xcodebuild \
  -workspace "$SCHEME.xcworkspace" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -quiet \
  build

if [[ ! -d "$APP" ]]; then
  echo "Build produced no $SCHEME.app: check the xcodebuild output above." >&2
  exit 1
fi
echo "==> Built $APP"
[[ "$1" == "--build" ]] && exit 0

echo '==> Installing'
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"

echo '==> Launching'
xcrun devicectl device process launch --device "$DEVICE_UDID" "$BUNDLE_ID" \
  || echo 'Launch refused (phone locked?): just tap the app icon.'
