#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
PY="${ROOT}/.venv/bin/python"
DIST="${ROOT}/dist"
DOWNLOADS="${ROOT}/../web/downloads"
APP="${DIST}/AirMouse Receiver.app"
mkdir -p "$DIST" "$DOWNLOADS"

"$PY" -m pip install -q -r requirements.txt pyinstaller dmgbuild
rm -rf "$DIST/AirMouse Receiver" "$APP" "$DIST/macos-stage" "$DIST/windows-stage" "$DIST/icon.iconset" "$DIST/icon.icns"

mkdir -p "$DIST/icon.iconset"
for size in 16 32 128 256 512; do
  /opt/homebrew/bin/rsvg-convert -w "$((size * 2))" -h "$((size * 2))" icon.svg -o "$DIST/icon.iconset/icon_${size}x${size}@2x.png"
  /opt/homebrew/bin/rsvg-convert -w "$size" -h "$size" icon.svg -o "$DIST/icon.iconset/icon_${size}x${size}.png"
done
iconutil -c icns "$DIST/icon.iconset" -o "$DIST/icon.icns"

"$PY" -m PyInstaller --noconfirm --clean --windowed --onedir \
  --name "AirMouse Receiver" --icon "$DIST/icon.icns" \
  --osx-bundle-identifier com.nattakit.airmouse.receiver receiver_app.py

"$PY" - <<'PY'
from pathlib import Path
import plistlib
plist_path = Path("dist/AirMouse Receiver.app/Contents/Info.plist")
data = plistlib.loads(plist_path.read_bytes())
data.update({
    "CFBundleIdentifier": "com.nattakit.airmouse.receiver",
    "CFBundleName": "AirMouse Receiver",
    "CFBundleDisplayName": "AirMouse Receiver",
    "CFBundleShortVersionString": "1.0.0",
    "CFBundleVersion": "1.0.0",
    "LSMinimumSystemVersion": "13.0",
    "NSHighResolutionCapable": True,
    "NSLocalNetworkUsageDescription": "AirMouse ใช้เครือข่าย Wi‑Fi เพื่อรับคำสั่งจากโทรศัพท์",
})
plist_path.write_bytes(plistlib.dumps(data, sort_keys=False))
PY

codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"
rm -f "$DOWNLOADS/AirMouse-Receiver-mac.zip" "$DOWNLOADS/AirMouse-Receiver-mac.dmg"
ditto -c -k --norsrc --keepParent "$APP" "$DOWNLOADS/AirMouse-Receiver-mac.zip"
AIRMOUSE_APP_PATH="$APP" "$PY" -m dmgbuild -s "$ROOT/dmg_settings.py" \
  "AirMouse Receiver" "$DOWNLOADS/AirMouse-Receiver-mac.dmg"

WINVER=3.13.9
WIN="$DIST/windows-stage"
mkdir -p "$WIN/python" "$WIN/site-packages"
curl -fsSL "https://www.python.org/ftp/python/${WINVER}/python-${WINVER}-embed-amd64.zip" -o "$DIST/python-embed.zip"
unzip -oq "$DIST/python-embed.zip" -d "$WIN/python"
rm -rf "$DIST/wheels"
"$PY" -m pip download --only-binary=:all: --no-deps --platform win_amd64 --implementation cp --abi cp313 --python-version 3.13 -d "$DIST/wheels" websockets==17.4 pynput==1.8.2
"$PY" -m pip download --only-binary=:all: --no-deps --platform win_amd64 --python-version 3.13 -d "$DIST/wheels" six==1.17.0
mkdir -p "$WIN/python/Lib/site-packages"
for whl in "$DIST"/wheels/*.whl; do unzip -oq "$whl" -d "$WIN/python/Lib/site-packages"; done
pth=$(find "$WIN/python" -maxdepth 1 -name '*._pth' | head -1)
sed -i.bak '/^import site$/d' "$pth"
printf '\nLib\\site-packages\nimport site\n' >> "$pth"
cp receiver.py "$WIN/receiver.py"
cat > "$WIN/AirMouse-Receiver.bat" <<'EOF'
@echo off
cd /d "%~dp0"
python\python.exe receiver.py
pause
EOF
rm -f "$DOWNLOADS/AirMouse-Receiver-windows.zip"
(cd "$WIN" && zip -qr "$DOWNLOADS/AirMouse-Receiver-windows.zip" .)
echo "Built app, DMG, ZIP and Windows portable artifact in $DOWNLOADS"
