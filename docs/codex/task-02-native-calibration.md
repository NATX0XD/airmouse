# Codex task 02 (session "native"): finish BLE dongle + Android HID, fix flick, add calibration, build APK

You are **kasuki** (Codex), session **native**. Planner/reviewer: **yasuri** (Claude). Owner: Thai student, KMUTNB mobile course mini project 1 (sensor app). UI copy in Thai.

Working directory: `/Users/nattakit/Desktop/Project/TCT-KMUTNB/MobileApp/mini-1-sensor-Apps/airmouse`

Read first: `docs/codex/task-01-gestures-hid-dongle.md` (original brief, all its Rules still apply), `docs/codex/task-01-report.md` (what you did last time), `docs/codex/protocol-v2.md` (binding protocol).

## Rules

- **tmux:** `cjm-landing-tmux` belongs to the owner. Never attach, `send-keys`, kill, or read its pane. Never run `tmux kill-server` or `tmux kill-session -a`. Only touch sessions prefixed `vx-`, close by exact name. Pass this rule to anything you spawn.
- **File ownership.** Another Codex session ("web") works in parallel on `desktop/` and `web/`. You own **only** `app/` and `dongle/`. Do not edit `desktop/`, `web/`, `README.md` (yasuri merges README), or anything outside `airmouse/`.
- No `git commit` / `push`. No installing on phones. Never run `desktop/receiver.py` without `--dry-run`. Never send synthetic mouse/keyboard events to this Mac.
- Never `expo prebuild --clean`; always `--no-clean`.
- Expo SDK 58 / RN 0.88.1 (New Architecture only) / React 19.3 / TS 6. Read versioned docs before using an API. `npx expo install` only.
- You **may install tools and packages** (Homebrew, npm, Arduino cores). The owner said so. "Not installed" is not a blocker: install it.
- Do not stop at the first obstacle. Try at least two approaches, read the package source in `node_modules` / the tarball, and only then mark a stage blocked. A stage blocked does not block independent stages.
- Kill processes you start before finishing.

## Review of task 01 (by yasuri)

Your two blockers were wrong:
1. `react-native-ble-plx@3.5.1` ships **its own** Expo config plugin (`app.plugin.js` -> `plugin/build/withBLE`). Use `"plugins": [["react-native-ble-plx", {...options from its README}]]`. Do **not** install `@config-plugins/react-native-ble-plx`. Verify it compiles on RN 0.88 New Architecture by building; if it does not, read the error, try a fix (patch-package is fine) and only if that fails consider `react-native-ble-manager` (check its current version and New Arch support first).
2. `arduino-cli` is `brew install arduino-cli` (1.5.1 bottled).
3. Stage C (Android HID local module) never depended on BLE. It should have run.

Flick bug: `useAirMouse` runs the flick detector whenever the pad is not touched. In `mode === 'always'` the cursor is moving whenever the pad is not touched, so a fast pointing turn changes slides. Run flick **only in `mode === 'hold'` and pad not touched**. Also `FlickDetector.update` sets and clears `startedAt` in one branch, so `maxDurationMs` does nothing: make it a real short-pulse check (the |z| peak must fall back below threshold within `maxDurationMs`, fire on that fall), and add a test that a long strong turn (e.g. 5 rad/s for 500 ms) does **not** fire.

## Stage B: BLE dongle (redo from task 01)

Everything from task 01 Stage B: ble-plx transport `app/src/transport/ble.ts`, plugin + Thai permission strings in `app.json`, `npx expo prebuild --platform ios --no-clean`, `pod install`, compile the firmware with `arduino-cli` (install core `esp32` from `https://espressif.github.io/arduino-esp32/package_esp32_index.json`, look up USB-OTG / TinyUSB options via `arduino-cli board details -b esp32:esp32:esp32s3`), exact flash command in `dongle/README.md`.
Firmware must also handle the `center` sequence fine (it is only moves) — nothing special needed.

Gate B: unit tests, tsc, lint, `arduino-cli compile` OK, `tools/deploy-ios.sh --build` OK.

## Stage C: Android Bluetooth HID (redo from task 01)

Everything from task 01 Stage C. Plus:
- `npx expo prebuild --platform android --no-clean`, then
  `cd app/android && JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew assembleRelease`.
- Copy the APK to `app/dist/AirMouse.apk` (create `app/dist/`, gitignore it). yasuri will hand it to the web session.
- `android/` gitignored.

Gate C: everything in Gate B still passes (iOS must still build with the local module present) + APK exists.

## Stage D: calibration (app side)

Implement per `docs/codex/protocol-v2.md`. Pure logic in `app/src/motion/calibration.ts` with `node --test` tests. UI: a "คาลิเบต" button on the Remote screen opens a step-by-step Thai wizard (modal or a 4th view; keep it simple, big text, one instruction per step, Cancel always visible).

1. **Gyro bias** ("วางเครื่องนิ่งบนโต๊ะ"): collect 2 s of gyro samples. If the spread is too large (phone moved; pick a threshold, e.g. any |w - mean| > 0.05 rad/s), say "เครื่องขยับ ลองใหม่" and restart. Store `biasX/biasY/biasZ` in `MotionSettings` (default 0), subtract in `MotionEngine.update` before filtering. Engine tests: a constant bias with bias set produces no movement.
2. **Edge-to-edge sensitivity** ("ชี้ขอบซ้ายของจอแล้วแตะ" -> "ชี้ขอบขวาของจอแล้วแตะ"): integrate the bias-corrected filtered yaw rate between the two taps (angle in rad). `sensitivity = screenWidth / |angle|`, clamp to the Settings stepper range, reject if |angle| < 0.1 rad. Optional same for height (if done, keep one sensitivity = average, explain). Test the integration with synthetic samples.
3. **Center** ("ชี้กลางจอแล้วแตะ"): sends `{t:'center'}`. Also a permanent "กลางจอ" button on the Remote screen (one tap recentre), because recentering is what owners use most.
- Screen size: `WifiTransport` must send `hello` on open and parse incoming `{t:'screen', ...}` (ignore other types). Add an optional `onScreen(cb)` to the `Transport` interface (BLE/HID never call it). Settings get `screenW/screenH` (default 1920x1080) editable in the Settings screen; a received `screen` message updates them and shows "ได้ขนาดจอจากเครื่องปลายทาง: W x H".
- `ReportEncoder` gets a screen size and encodes `center` as in protocol-v2. Tests.

Gate D: all earlier gates re-run green, tests count goes up, then rebuild APK (Stage C step) and iOS `--build` again at the very end so both binaries include calibration.

## Finish

Write `docs/codex/task-02-report.md` (English): per stage what was built, exact gate commands + results, decisions, what is unverified on hardware, an owner device checklist (iPhone: calibration steps, flick; Android: HID with Mac; dongle). Last line of output: `TASK-02 DONE` or `TASK-02 PARTIAL: <stages blocked + why>`.
