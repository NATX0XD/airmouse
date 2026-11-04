# Codex task 04: real macOS app for the receiver ("AirMouse Receiver.app")

You are **kasuki** (Codex). Planner/reviewer: **yasuri** (Claude). Owner: Thai student; UI copy Thai (short English sub-labels OK).

Working directory: `/Users/nattakit/Desktop/Project/TCT-KMUTNB/MobileApp/mini-1-sensor-Apps/airmouse`

## Why

Owner feedback: "ใน MacBook ยังไม่มี app เลย". Task 03 shipped a loose onefile binary + `.command` in a zip; that is not an app. The owner expects to double-click an app in /Applications, see a window with the IP to type into the phone, and have it work.

## Rules

- **tmux:** `cjm-landing-tmux` belongs to the owner. Never attach, `send-keys`, kill, or read its pane. Never run `tmux kill-server` / `tmux kill-session -a`. Only `vx-` sessions, close by exact name.
- You own `desktop/` and `web/` only. Do not edit `app/`, `dongle/`, `README.md`.
- No git commit/push. No deploying the site.
- **Do NOT launch the GUI app or any window on this Mac, do not move the mouse, do not run the receiver without `--dry-run`.** The owner is using the Mac. yasuri launches the app after review. Test logic headlessly.
- Do not copy anything into `/Applications` (yasuri does that).
- `/opt/homebrew/bin/python3.13` venv in `desktop/.venv`. You may `brew install` / `pip install`. Check current versions/docs online.
- A user-run receiver may be running from the owner's terminal (`python receiver.py`, port 8765). Do not kill it. Use other ports in tests.

## Build

1. GUI receiver `desktop/receiver_app.py` (keep `receiver.py` as the CLI and shared core; import its `handle`, outputs, `screen_info`, `local_ips` instead of duplicating):
   - Toolkit: pick the one that packages cleanly with PyInstaller on Apple Silicon and Homebrew Python 3.13. Options: tkinter (needs `brew install python-tk@3.13`), or AppKit through PyObjC (already partly installed with pynput). Decide, explain in the report.
   - The asyncio WebSocket server runs in a background thread; the UI updates through the toolkit's thread-safe mechanism.
   - Window (~420x520, clean, dark or light but readable, big type):
     - Title "AirMouse Receiver".
     - Big IP + port to type into the phone (the routed IP first; others smaller). A "คัดลอก" button.
     - Status line: "รอโทรศัพท์เชื่อมต่อ…" / "เชื่อมต่อแล้ว: <phone ip>" with a coloured dot. Message rate (msg/s) small.
     - **Accessibility check**: use `AXIsProcessTrusted()` (ApplicationServices/HIServices via PyObjC or ctypes). If not trusted: a red banner "ยังไม่ได้อนุญาต Accessibility — เคอร์เซอร์จะไม่ขยับ" + button "เปิดการตั้งค่า" that calls `AXIsProcessTrustedWithOptions({kAXTrustedCheckOptionPrompt: True})` and/or opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. Re-check every 2 s and turn green when granted.
     - Screen size line ("จอ 2560 x 1080") so calibration makes sense.
     - Port field (default 8765) + restart if changed (optional, keep simple).
   - Closing the window quits the app (stop server cleanly).
   - If the port is busy (e.g. CLI receiver already running), show a clear Thai error instead of crashing.
2. PyInstaller `--windowed` app bundle `desktop/dist/AirMouse Receiver.app`:
   - `CFBundleIdentifier` `com.nattakit.airmouse.receiver`, `CFBundleName`/`CFBundleDisplayName` "AirMouse Receiver", version 1.0.0, `NSLocalNetworkUsageDescription` (Thai), `LSMinimumSystemVersion` sensible, `NSHighResolutionCapable` true.
   - An app icon (`.icns`) generated from a simple vector design (cursor + phone, consistent with `web/` colours) with `iconutil`.
   - Ad-hoc sign the whole bundle deep (`codesign --force --deep -s -`) and verify with `codesign --verify --deep --strict`.
   - Stable bundle id + signature matters: Accessibility permission is tied to it. Note in the report that re-signing ad-hoc after a rebuild may require re-granting Accessibility.
3. Packaging into `web/downloads/`:
   - `AirMouse-Receiver-mac.dmg` with the app and an `/Applications` symlink (use `dmgbuild` from pip — headless; do NOT use create-dmg, it drives Finder). Keep `AirMouse-Receiver-mac.zip` too but make it contain the `.app` (ditto `--keepParent`), no `__MACOSX`, no loose binary.
   - Update `web/update-downloads.sh` + `web/index.html` copy: mac download = dmg (zip as secondary link), instructions: open dmg, drag to Applications, first open = right-click > Open, then press "เปิดการตั้งค่า" in the app to allow Accessibility.
   - `desktop/build.sh` builds CLI-free mac app + dmg + zip + the existing Windows zip.
4. Tests (headless): unit tests for any new pure logic (status text formatting, IP ordering already exists), `python -m unittest` all green; build the app; run the **bundled** binary inside the .app in a mode that does not show UI and does not move the mouse — add `--selftest` to `receiver_app.py`: starts the server in dry-run on a given port, waits for one client hello, replies screen, exits 0. Drive it with a websockets client from the test. Also `--dry-run` flag for the GUI (yasuri uses it for a first look).

## Finish

`docs/codex/task-04-report.md`: toolkit decision, how to run, verification commands + results, artifacts with sizes, risks (Gatekeeper, Accessibility re-grant after rebuild, Intel Macs unsupported). Last line: `TASK-04 DONE` or `TASK-04 PARTIAL: <why>`.
