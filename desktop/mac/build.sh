#!/usr/bin/env bash
# Builds desktop/mac/dist/AirMouse.app (release, icon, Info.plist, signed with the stable identity).
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${AIRMOUSE_SIGN_IDENTITY:-Apple Development: nattakit982547@gmail.com (YYXH3GUSWN)}"
VERSION="1.0.0"
BUILD_NUMBER="${AIRMOUSE_BUILD:-$(date +%Y%m%d%H%M)}"
APP="dist/AirMouse.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/AirMouse"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AirMouse"

# Icon: rendered offscreen from the SwiftUI vector art (never shows a window).
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# Drop-in override: Resources/AppIcon-1024.png (e.g. Codex art from assets-gen/icon/mac-icon-1024.png).
OVERRIDE="Resources/AppIcon-1024.png"
if [[ -f "$OVERRIDE" ]]; then
  echo "Icon: using $OVERRIDE"
  mkdir -p "$TMP/AppIcon.iconset"
  for base in 16 32 128 256 512; do
    sips -z "$base" "$base" "$OVERRIDE" --out "$TMP/AppIcon.iconset/icon_${base}x${base}.png" >/dev/null
    sips -z "$((base * 2))" "$((base * 2))" "$OVERRIDE" --out "$TMP/AppIcon.iconset/icon_${base}x${base}@2x.png" >/dev/null
  done
else
  echo "Icon: code-drawn (no $OVERRIDE)"
  "$BIN" --render-icon "$TMP/AppIcon.iconset" >/dev/null
fi
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$TMP/AppIcon.iconset"

# Optional Codex illustrations (assets-gen/); the app falls back to code-drawn vectors.
ASSETS="../../assets-gen"
for src in "illustrations/hero-pointing.png" "infographics/how-it-works.png"; do
  if [[ -f "$ASSETS/$src" ]]; then
    mkdir -p "$APP/Contents/Resources/Illustrations"
    cp "$ASSETS/$src" "$APP/Contents/Resources/Illustrations/"
    echo "Illustration: $src"
  fi
done
for src in mac3d/iphone-remote.png mac3d/target.png mac3d/cursor-click.png mac3d/shield-check.png mac3d/waves.png mac3d/gauge.png mac3d/info.png; do
  if [[ -f "$ASSETS/$src" ]]; then
    mkdir -p "$APP/Contents/Resources/Illustrations"
    cp "$ASSETS/$src" "$APP/Contents/Resources/Illustrations/"
    echo "Illustration: $src"
  fi
done
if [[ -d "$ASSETS/explainer" ]]; then
  mkdir -p "$APP/Contents/Resources/Illustrations/explainer"
  cp "$ASSETS/explainer/"*.png "$APP/Contents/Resources/Illustrations/explainer/"
  echo "Illustrations: explainer/*.png"
fi
if [[ -d "$ASSETS/explainer/sensors" ]]; then
  mkdir -p "$APP/Contents/Resources/Illustrations/explainer/sensors"
  cp "$ASSETS/explainer/sensors/"*.png "$APP/Contents/Resources/Illustrations/explainer/sensors/"
  echo "Illustrations: explainer/sensors/*.png"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>AirMouse</string>
  <key>CFBundleIdentifier</key><string>com.nattakit.airmouse.mac</string>
  <key>CFBundleName</key><string>AirMouse</string>
  <key>CFBundleDisplayName</key><string>AirMouse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><false/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Nattakit. Course project, KMUTNB.</string>
  <key>NSLocalNetworkUsageDescription</key><string>AirMouse listens on your local network so your iPhone can connect and move the pointer.</string>
  <key>NSBonjourServices</key><array><string>_airmouse._tcp</string></array>
  <key>NSBluetoothAlwaysUsageDescription</key><string>AirMouse uses Bluetooth so your iPhone can control the pointer without Wi-Fi.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

codesign --force --deep --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Built $(pwd)/$APP"
