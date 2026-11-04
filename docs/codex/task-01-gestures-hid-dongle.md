# Codex task 01: gestures, Android Bluetooth HID, ESP32-S3 BLE dongle

You are **kasuki** (Codex). Planner/reviewer is **yasuri** (Claude). Owner: Thai student, KMUTNB mobile app course, "mini project 1: sensor app". All UI copy is Thai.

Working directory: `/Users/nattakit/Desktop/Project/TCT-KMUTNB/MobileApp/mini-1-sensor-Apps/airmouse`

## Rules (read first)

- **tmux:** `cjm-landing-tmux` belongs to the owner. Never attach, `send-keys`, kill, or read its pane. Never run `tmux kill-server` or `tmux kill-session -a`. Only create/touch sessions prefixed `vx-`, close them by exact name. Pass this rule to any session you spawn.
- Do **not** touch `../mobile/`, `../flight/`, `../docs/`, `../tools/` (other projects in the same repo).
- Do **not** `git commit`, `git push`, or change git config. yasuri reviews the diff and commits.
- Do **not** install the app on the phone and do **not** run `desktop/receiver.py` without `--dry-run` (it moves the owner's real mouse). Never send synthetic mouse/keyboard events to this Mac.
- Never `npx expo prebuild --clean`. Always pass `--no-clean` (clean deletes `ios/`, which holds a working signed setup).
- `app/AGENTS.md`: Expo changes every SDK. This is **Expo SDK 58 / RN 0.88.1 / React 19.3 / TS 6**. Before using any Expo/RN API, read the versioned docs `https://docs.expo.dev/versions/v58.0.0/` (and `https://docs.expo.dev/llms.txt`). Install packages with `npx expo install <pkg>` only. Check a library's current README/release notes before use; do not answer from memory.
- Keep the existing style: small files, comments explain *why*, pure logic separated from React Native so it is testable with `node --test`.
- Kill every process you start (Metro, gradle daemons are fine to leave, but no servers / receivers left running) before you finish.

## What exists (working on the owner's iPhone 15, iOS 27, confirmed by owner)

```
app/                      Expo SDK 58 app "AirMouse", bundle/package com.nattakit.airmouse
  App.tsx                 3 tabs (รีโมต / เซนเซอร์ / ตั้งค่า), keep-awake, safe area
  src/motion/engine.ts    gyro -> integer dx/dy: One Euro filter, dead zone, clutch, sub-pixel remainder (pure)
  src/motion/engine.test.ts  9 node:test cases
  src/transport/types.ts  Msg union {move, button, scroll, key} + Transport interface
  src/transport/wifi.ts   WebSocket to desktop receiver, auto-reconnect
  src/useAirMouse.ts      gyro @16 ms -> engine -> transport.send; history ring for charts
  src/settings.ts         AsyncStorage settings (motion, mode hold|always, host, port)
  src/screens/{Remote,Sensors,Settings}Screen.tsx
  ios/                    prebuilt, gitignored, builds with ../tools/deploy-ios.sh --build
desktop/receiver.py       websockets 17 + pynput, JSON msgs, --dry-run
tools/deploy-ios.sh       Release build (+ install/launch; you only use --build)
README.md
```

Axis convention (verified on device): phone portrait, top edge toward the screen, display up. Yaw = -gyro.z -> dx, pitch = +gyro.x -> dy = -pitch.

Run current checks once at the start to see the baseline is green:
```
cd app && npm test && npx tsc --noEmit && npx expo lint
```

## Goal

One app, three ways out of the phone, picked in the app:

| Mode | Phone | Target | Install on target |
|---|---|---|---|
| WiFi (exists) | iPhone + Android | Mac/PC | receiver.py |
| BLE dongle (new) | iPhone + Android | TV/Mac/PC via USB | nothing (dongle is a USB mouse) |
| Bluetooth HID (new) | Android 9+ only | TV/Mac/PC | nothing (phone pairs as a BT mouse) |

iOS cannot act as a HID device (CoreBluetooth blocks HID service 0x1812), so the HID mode must be hidden/disabled on iOS with a Thai explanation, not crash.

Do the stages **in order**. Each stage must end green before the next.

---

## Stage A: shared binary report + gestures + transport picker (works on iPhone today)

1. `app/src/transport/report.ts` (pure, tested in `report.test.ts`):
   - 5-byte mouse report used by BLE dongle and Android HID:
     `[buttons, dx, dy, wheel, key]` — buttons bit0 = left, bit1 = right; dx/dy/wheel int8 (-127..127, two's complement in a Uint8Array); key 0 none, 1 = Left arrow, 2 = Right arrow.
   - A small stateful `ReportEncoder` that turns the existing `Msg` stream into reports: keeps the current button state, splits large dx/dy/scroll into several reports so nothing is clipped, never loses a button-up.
   - Scroll sign: Msg `scroll.dy > 0` means scroll down (content moves up). HID wheel positive = scroll up. Encode `wheel = -dy`. Document it.
   - Tests: button down/up sequence, dx 300 -> 127,127,46, negative values, wheel sign, key report followed by key-release (key 0) report.
2. Gesture: **flick to change slides** when the clutch is NOT held (presentation mode).
   - Pure detector `app/src/motion/gesture.ts` + tests: input gyro samples, output `'left' | 'right' | null`. A quick yaw flick (|z| over a threshold, e.g. 4 rad/s, short duration) then a refractory period (~600 ms) so the return swing does not fire the opposite direction. Pick sensible defaults and write down why; the owner will tune on device.
   - Wire into `useAirMouse.ts`: only when a new setting `flickSlides` (default true) is on and the pad is not being touched. Sends `{t:'key', k}` and a light haptic.
   - Settings screen: switch "สะบัดเพื่อเปลี่ยนสไลด์".
3. Transport picker on the Remote screen: segment `WiFi | ดองเกิล BLE | Bluetooth HID` stored in settings (`transport: 'wifi' | 'ble' | 'hid'`). Show only the fields for the chosen mode (IP/port for WiFi, scan/connect for BLE, pair/connect for HID). HID disabled on iOS with text "iPhone ใช้โหมดนี้ไม่ได้ (Apple ไม่อนุญาตให้แอปเป็นเมาส์ Bluetooth) ใช้ดองเกิล BLE แทน".
   - Keep `Transport` as the single interface. `useAirMouse` creates the right one.
4. Gate A: `npm test`, `npx tsc --noEmit`, `npx expo lint` all clean; `npx expo export --platform ios --platform android --output-dir <tmp>` bundles.

## Stage B: ESP32-S3 dongle firmware + BLE transport

Hardware the owner will buy: an ESP32-S3 dev board with native USB (e.g. ESP32-S3-DevKitC-1 or a Super Mini). Not here yet, so compile-only.

1. `dongle/airmouse_dongle/airmouse_dongle.ino` (Arduino-ESP32 core 3.x):
   - BLE peripheral, name `AirMouse-Dongle`, one custom 128-bit service with one characteristic (write + write-without-response) that receives one or more 5-byte reports (accept a write whose length is a multiple of 5).
   - USB HID out: `USB.h` + `USBHIDMouse` + `USBHIDKeyboard` (TinyUSB in the core). Apply buttons (press/release on change), move, wheel, key tap.
   - Release all buttons on BLE disconnect (no stuck drag). Restart advertising on disconnect.
   - Optional status LED if the board has one (guard with a define).
   - Prefer the core's built-in BLE library or NimBLE-Arduino — check which is current and supported on core 3.x before choosing; write the choice and reason in `dongle/README.md`.
   - Put UUIDs in one header, and mirror them in `app/src/transport/bleIds.ts`.
2. Compile with `arduino-cli` (install via Homebrew if missing; install the esp32 core from Espressif's official board index). FQBN for S3 with USB-OTG mode (USB Mode = USB-OTG (TinyUSB)), e.g. `esp32:esp32:esp32s3:USBMode=default` — look up the exact option names with `arduino-cli board details`. Write the exact flash command in `dongle/README.md` (Thai, short), including how to enter download mode (hold BOOT, tap RESET) and which USB port to use.
3. App BLE transport `app/src/transport/ble.ts` using **react-native-ble-plx** (current 3.5.x; confirm its Expo config plugin and permissions for SDK 58). Scan for the service UUID, connect, request a bigger MTU on Android, write reports with write-without-response. Batch reports produced within one gyro tick into a single write. Status/errors in Thai. Reconnect on drop like `wifi.ts`.
   - Add the plugin + iOS `NSBluetoothAlwaysUsageDescription` (Thai) + Android BLE permissions to `app.json`.
   - Then `npx expo prebuild --platform ios --no-clean` and `cd ios && pod install` so the iOS project includes it.
4. Gate B: Stage A checks + `arduino-cli compile` succeeds + `../tools/deploy-ios.sh --build` succeeds (run from `airmouse/`: `tools/deploy-ios.sh --build`).

## Stage C: Android Bluetooth HID (phone as a real BT mouse)

1. Local Expo module `app/modules/airmouse-hid` (create with `npx create-expo-module@latest --local`, Kotlin, Android only; iOS side returns `isSupported() = false`).
   - Android API 28+ `BluetoothHidDevice`: get the profile proxy, `registerApp` with an SDP record + a standard boot-compatible mouse report descriptor that matches our 5-byte report (3 buttons, X, Y, wheel; keep the key byte for a second report ID with a keyboard descriptor, or send arrow keys through a consumer/keyboard report — choose one, explain).
   - JS API: `isSupported()`, `register()`, `getBondedDevices()`, `connect(address)`, `disconnect()`, `send(report: Uint8Array | number[])`, and an event for connection state. Request runtime permissions `BLUETOOTH_CONNECT` (+ `BLUETOOTH_SCAN`/`ADVERTISE` if needed) and offer "make discoverable" (`ACTION_REQUEST_DISCOVERABLE`) for first pairing.
   - Note in comments: some OEMs disable the HID Device profile; `registerApp` fails -> show Thai message suggesting the BLE dongle.
2. `app/src/transport/hid.ts` implementing `Transport` on top of the module, using `ReportEncoder`.
3. Android build: `npx expo prebuild --platform android --no-clean` then
   `cd android && JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew assembleRelease` (ANDROID_HOME=~/Library/Android/sdk). APK must build. Note the APK path in the README.
   - Make sure `android/` is gitignored like `ios/`.
4. Gate C: all earlier gates still pass (re-run iOS `--build` too: the local module must not break iOS) + `assembleRelease` succeeds.

---

## Finish

- Update `README.md` (Thai): status per mode, what is verified (tests/builds) vs **not verified on hardware** (Android HID, dongle — say so plainly), how to run each mode, how to flash the dongle.
- Write `docs/codex/task-01-report.md` (English, short): what you built per stage, gate results with the exact commands, decisions + reasons, anything skipped, risks, and a device test checklist for the owner (iPhone gestures, iPhone+dongle, Android HID on Mac / TV).
- If a stage is blocked (e.g. tool cannot install), stop that stage, write why in the report, continue with the next stage only if it does not depend on it.
- Last line of your output: `TASK-01 DONE` or `TASK-01 BLOCKED: <reason>`.
