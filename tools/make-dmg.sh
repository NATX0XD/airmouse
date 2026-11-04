#!/usr/bin/env bash
# Usage: tools/make-dmg.sh [path/to/AirMouse.app]
# Packages the app into web/downloads/AirMouse.dmg and writes manifest.json.
# Upload the DMG as a GitHub Release asset (web/downloads/ is gitignored):
#   gh release create vX.Y.Z web/downloads/AirMouse.dmg
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/desktop/mac/dist/AirMouse.app}"
OUT="$ROOT/web/downloads"
[ -d "$APP" ] || { echo "App not found: $APP" >&2; exit 1; }
mkdir -p "$OUT"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/AirMouse.app"
rm -f "$OUT/AirMouse.dmg"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg --volname AirMouse --window-size 540 340 --icon-size 96 \
    --icon AirMouse.app 140 160 --app-drop-link 400 160 \
    "$OUT/AirMouse.dmg" "$STAGE" >/dev/null
else
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname AirMouse -srcfolder "$STAGE" -ov -format UDZO "$OUT/AirMouse.dmg" >/dev/null
fi
VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0.0)"
SIZE="$(stat -f%z "$OUT/AirMouse.dmg")"
SHA="$(shasum -a 256 "$OUT/AirMouse.dmg" | awk '{print $1}')"
cat > "$OUT/manifest.json" <<JSON
{"name":"AirMouse","version":"$VER","file":"AirMouse.dmg","size":$SIZE,"sha256":"$SHA","date":"$(date -u +%F)"}
JSON
echo "$OUT/AirMouse.dmg ($SIZE bytes) v$VER"
