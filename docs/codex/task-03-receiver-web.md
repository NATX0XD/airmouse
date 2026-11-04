# Codex task 03 (session "web"): desktop receiver v2 + Mac/Windows installers + landing page

You are **kasuki** (Codex), session **web**. Planner/reviewer: **yasuri** (Claude). Owner: Thai student, KMUTNB mobile course mini project 1 (sensor app). All user-facing copy in Thai.

Working directory: `/Users/nattakit/Desktop/Project/TCT-KMUTNB/MobileApp/mini-1-sensor-Apps/airmouse`

Project: **AirMouse** turns a phone into an air mouse (like an LG Magic Remote): the phone's gyroscope moves the cursor on a computer. Read `README.md`, `desktop/receiver.py`, and the binding protocol `docs/codex/protocol-v2.md`.

## Rules

- **tmux:** `cjm-landing-tmux` belongs to the owner. Never attach, `send-keys`, kill, or read its pane. Never run `tmux kill-server` or `tmux kill-session -a`. Only touch sessions prefixed `vx-`, close by exact name. Pass this rule to anything you spawn.
- **File ownership.** Another Codex session ("native") works in parallel on `app/` and `dongle/`. You own **only** `desktop/` and `web/`. Do not edit `app/`, `dongle/`, `README.md` (yasuri merges it), or anything outside `airmouse/`.
- No `git commit` / `push`. No deploying the website anywhere (yasuri asks the owner where to host).
- **Never move the owner's real mouse or press keys on this Mac.** Run the receiver only with `--dry-run` in tests. Do not launch the packaged app in non-dry-run mode. Pure logic (message handling, center maths) must be testable without pynput.
- If you open a browser for screenshots (Playwright), close it when done. Kill every server/process you start before finishing.
- You may install tools (Homebrew, pip into `desktop/.venv`, npm in `web/`). "Not installed" is not a blocker. Use `/opt/homebrew/bin/python3.13` (system python3.9 cannot build pyobjc).
- Check current docs/versions online before using a library; do not answer from memory.

## Stage A: receiver v2 (`desktop/receiver.py`)

Implement protocol v2:
- Reply to `hello` with `{t:'screen', w, h, scale}` for the main display. macOS: logical points (what `pynput` moves in). Windows: call `SetProcessDpiAwareness`/`SetProcessDPIAware` at start so sizes and moves are in real pixels. Find the screen size without heavy deps if possible (macOS: Quartz via pyobjc, already installed with pynput; Windows: ctypes `GetSystemMetrics`). Also send `screen` again if it changes (poll every few seconds per connection, cheap).
- `{t:'center'}` -> set absolute cursor position to the centre of the main screen (`mouse.position = (w//2, h//2)`).
- Ignore unknown message types silently (log once per type in verbose mode).
- Keep `--dry-run` (prints, incl. "center -> (x, y)"), `--port`. Add `--verbose`.
- Startup text, big and clear (Thai + English): IP address(es) to type in the app (list all non-loopback IPv4s, mark the likely one), port, and the macOS Accessibility hint.
- Tests: `desktop/test_receiver.py` with `unittest` (or pytest in the venv): handle() for every message type with a fake output, bad/unknown messages don't raise, center maths. Plus an end-to-end test in dry-run: start server on a random port, connect with `websockets` client, send hello -> receive screen, send center/move. Run them.

## Stage B: installers

Build into `desktop/dist/` (gitignored), then copy final artifacts into `web/downloads/`.

1. **macOS**: PyInstaller (current version, in the venv) -> `AirMouse Receiver.app` (windowed is NOT required; a console app is fine and simpler — but double-clicking a .app has no visible console, so either a) build a .app that opens Terminal running the receiver, or b) ship a `.command` launcher inside a zip with the onefile binary. Pick whatever actually shows the IP to the user on double-click, explain why.) Include `NSLocalNetworkUsageDescription` if needed for incoming connections. Ad-hoc codesign (`codesign -s -`). Zip -> `web/downloads/AirMouse-Receiver-mac.zip`. Note: Apple Silicon build; say so on the page. Verify: run the built binary with `--dry-run` and the e2e client test against it.
2. **Windows** (we are on a Mac, no cross-compiling PyInstaller): make a **portable zip** that needs no install:
   - official Python **embeddable** package for Windows amd64 from python.org (pick the current 3.13.x, verify the URL exists),
   - `pip download --platform win_amd64 --only-binary=:all: --python-version 3.13` wheels for `websockets` and `pynput` (and their deps), unpacked into the embeddable's site-packages (edit the `._pth` file so `import site` / the lib folder is on the path),
   - `receiver.py` + `AirMouse-Receiver.bat` that runs `python\python.exe receiver.py` and pauses on exit,
   - -> `web/downloads/AirMouse-Receiver-windows.zip`.
   - Verify what you can on macOS: zip layout, `._pth` contents, that every import's wheel is present (e.g. list site-packages, check pynput's win32 backend files exist). Mark "not run on Windows" clearly in the report and on the page (small note).
   - Also add `desktop/README.md` (Thai) with the run-from-source way for both OSes as a fallback.
3. `desktop/build.sh` that rebuilds both artifacts reproducibly.

## Stage C: landing page (`web/`)

A single static site (plain HTML/CSS/JS, no framework, no build step, works from any static host and from a local http server). Thai copy, mobile-first, fast, good-looking but not generic AI style: concrete product visuals (an SVG illustration of a phone pointing at a laptop/TV with a cursor path), real content.

Sections:
1. Hero: "AirMouse — ใช้มือถือเป็นเมาส์ชี้กลางอากาศ" + one-line explanation + two primary buttons: "ดาวน์โหลดแอป Android" and "ดาวน์โหลดตัวรับบนคอม".
2. ใช้งานยังไง: 3 steps (install receiver on the computer, install app on the phone, same WiFi -> type IP -> hold the pad and point). Plus calibration in one line (กลางจอ / คาลิเบต).
3. ดาวน์โหลด, two groups:
   - **ติดตั้งบนโทรศัพท์ (ต้นทาง)**: Android APK `downloads/AirMouse.apk` (with how to allow "Install unknown apps"); iPhone card = "เร็วๆ นี้" (disabled).
   - **ติดตั้งบนคอม (ปลายทาง)**: macOS (Apple Silicon) zip, Windows zip. Each with 3-line install instructions (macOS: right-click > Open first time because the app is not notarised, then allow Accessibility; Windows: unzip, run the .bat, allow firewall for private networks).
   - Show file size next to each link (generate at build time with a tiny script `web/update-downloads.sh` that writes `web/downloads/manifest.json`; the page reads it and also hides a button if the file is missing, showing "ยังไม่พร้อม").
4. โหมดเชื่อมต่อ: WiFi / ดองเกิล ESP32-S3 / Bluetooth HID (Android) table, honest about which need nothing installed on the target and which are experimental.
5. เซนเซอร์ที่ใช้: gyroscope (main), accelerometer, (sensor fusion idea), touch — short, educational (it's a sensor course).
6. FAQ: เคอร์เซอร์ไม่ขยับ (Accessibility), เชื่อมต่อไม่ได้ (same WiFi, university WiFi blocks devices → use hotspot, firewall), iPhone?
7. Footer: course + project name.

`downloads/AirMouse.apk` will be copied in by yasuri from the other session; until then the manifest marks it missing and the button shows "ยังไม่พร้อม". Do not create a fake APK.

Verify: serve `web/` with `python3 -m http.server` on a free port, screenshot at 390px and 1280px widths (Playwright/headless Chrome; on this Mac headless Chrome min window width is 500px, so check with innerWidth or use device emulation), check no horizontal overflow, links resolve (200 or intentionally missing), manifest loads. Save screenshots to `web/.screenshots/` (gitignored). Close browser + server.

## Finish

Write `docs/codex/task-03-report.md` (English): per stage what was built, exact verification commands + results, decisions, unverified items (Windows never run; Mac app real-mouse mode not run by you), and an owner checklist. Last line of output: `TASK-03 DONE` or `TASK-03 PARTIAL: <reason>`.
