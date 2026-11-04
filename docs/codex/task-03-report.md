# Task 03 report

## Stage A — receiver v2

- `desktop/receiver.py` now implements protocol v2 `hello -> screen`, `center`, relative move, buttons, scroll, arrow keys, malformed-message tolerance, and one-time verbose logging for unknown types.
- macOS uses Quartz main-display logical bounds and reports a backing scale. Windows sets DPI awareness before using `GetSystemMetrics`, so reported coordinates are physical pixels. Other platforms have a lightweight fallback.
- A three-second per-connection poll sends a new `screen` message when the display changes.
- Startup lists all discovered non-loopback IPv4 addresses, marks the first likely Wi-Fi address, prints port, and prints the macOS Accessibility instructions.
- `DryOutput` prints `center -> (x, y)` and no real mouse or keyboard is touched in tests.

Verification:

```sh
cd desktop
.venv/bin/python -m unittest -v test_receiver.py
```

Result: 2 tests passed. This covered every message type, malformed/unknown messages, odd-size center math, and a real WebSocket dry-run connection.

The packaged macOS binary was also started with `--dry-run --port 51241`; a WebSocket client received `{"t":"screen","w":2560,"h":1080,"scale":1.0}` and sent `center` and `move`. The process was stopped afterward. It printed the expected startup text and dry-run events.

## Stage B — installers

`desktop/build.sh` rebuilds both artifacts. It uses the current installed PyInstaller 6.22.3 and Python 3.13.14 on this Apple Silicon Mac.

- macOS: `web/downloads/AirMouse-Receiver-mac.zip` contains an Apple Silicon one-file console binary and `Run AirMouse Receiver.command`. The launcher opens the receiver in a visible Terminal, which is intentional so the user can read the IP and port. The binary is ad-hoc signed with `codesign -s -`.
- Windows: `web/downloads/AirMouse-Receiver-windows.zip` contains the official CPython 3.13.9 win-amd64 embeddable distribution, `websockets` 17.4, `pynput` 1.8.2, `six`, the edited `python313._pth`, `receiver.py`, and `AirMouse-Receiver.bat`.
- `web/update-downloads.sh` regenerates `web/downloads/manifest.json`; the landing page hides unavailable download links and displays `ยังไม่พร้อม`.

Commands and results:

```sh
./desktop/build.sh
./web/update-downloads.sh
```

Result: both zip files built successfully. The manifest reports macOS 9.6 MB and Windows 10.8 MB; APK is intentionally missing until the native session copies it in.

```sh
unzip -l web/downloads/AirMouse-Receiver-windows.zip
cat desktop/dist/windows-stage/python/python313._pth
find desktop/dist/windows-stage/python/Lib/site-packages/pynput -type f
```

Result: Windows zip layout, `Lib\\site-packages` plus `import site`, and Win32 keyboard/mouse backend files were present. Windows was not run on Windows and is therefore not hardware/runtime verified.

## Stage C — landing page

Added a buildless Thai static site in `web/`: responsive editorial layout, SVG phone/laptop cursor-path illustration, setup steps, downloads, connection-mode table, sensor explanations, FAQ, footer, manifest-driven file sizes/status, and truthful Windows/iPhone experimental notes. No fake APK was created.

Browser verification:

```sh
python3 -m http.server 51242 --directory web
```

Using Playwright CLI, screenshots were saved to `web/.screenshots/landing-390.png` and `web/.screenshots/landing-1280.png`. At both 390px and 1280px, `scrollWidth === innerWidth` (no horizontal overflow). Manifest loaded with HTTP 200; macOS/Windows download links resolved with HTTP 200; the missing APK resolved with HTTP 404 and was intentionally rendered as `ยังไม่พร้อม`.

## Decisions and remaining risk

- Chose a visible `.command` launcher plus console binary for macOS because a windowless `.app` would hide the IP instructions on double-click.
- Windows packaging is static/portable verification only: not run on Windows, not firewall-tested, and not tested with a real Windows cursor.
- Real-mouse mode was not run on this Mac by design. Accessibility permission and physical cursor movement remain owner verification items.
- The APK remains absent until the native session provides the real artifact.

## Owner checklist

- [ ] Copy the real `AirMouse.apk` into `web/downloads/` and run `./web/update-downloads.sh`.
- [ ] Test the macOS launcher on the owner Mac and grant Accessibility.
- [ ] Test the Windows zip on Windows 11, including Private-network firewall approval.
- [ ] Test phone-to-receiver movement and calibration on the same Wi-Fi/hotspot.
- [ ] Choose the final static hosting location and publish `web/`.
