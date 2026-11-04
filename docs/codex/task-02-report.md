# Task 02 report

## Stage B — BLE dongle

Implemented the real `react-native-ble-plx@3.5.1` transport. It scans for the shared service UUID, requests a larger MTU on Android when possible, batches reports from one JS tick into one write-without-response, reconnects after a drop, and reports Thai errors. The package's own config plugin is used with Thai `bluetoothAlwaysPermission`; no community config-plugin package was added. WiFi now sends protocol-v2 `hello` and accepts only valid `screen` replies.

The ESP32-S3 firmware uses the Arduino-ESP32 3.3.12 built-in BLE API and TinyUSB HID. It accepts one or more five-byte reports, releases buttons on disconnect, restarts advertising, and handles move/button/wheel/key reports.

Gate commands/results:

```text
cd app && npm test                         PASS (21 tests)
cd app && npx tsc --noEmit                 PASS
cd app && npx expo lint                    PASS
cd app && npx expo prebuild --platform ios --no-clean  PASS
cd app/ios && pod install                  PASS (react-native-ble-plx 3.5.1)
arduino-cli board details -b esp32:esp32:esp32s3  PASS; USB-OTG = USBMode=default
arduino-cli compile --fqbn esp32:esp32:esp32s3:USBMode=default dongle/airmouse_dongle  PASS
tools/deploy-ios.sh --build                PASS; Release AirMouse.app produced
```

## Stage C — Android Bluetooth HID

Added the local Android-only Expo module at `app/modules/airmouse-hid`. It registers `BluetoothHidDevice`, exposes support/register/bonded-device/connect/disconnect/send APIs, emits connection state, and sends a mouse report plus a separate keyboard report for arrow keys. OEMs that do not expose HID Device receive a Thai error suggesting the BLE dongle. iOS has no HID native implementation and remains disabled in the picker.

Gate commands/results:

```text
npx expo prebuild --platform android --no-clean  PASS
cd app/android && JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew --no-daemon assembleRelease  PASS
```

APK copied to `app/dist/AirMouse.apk` (72 MB). Native `android/` and `ios/` folders remain generated/ignored.

## Stage D — calibration and center

Added pure calibration logic and tests in `app/src/motion/calibration.ts`: two-second gyro bias averaging with a 0.05 rad/s spread rejection, bias-corrected yaw integration, and sensitivity derivation/clamping. `MotionEngine` subtracts stored `biasX/biasY/biasZ`; settings defaults remain zero. The Remote screen has a Thai step wizard with an always-visible Cancel button, a permanent `กลางจอ` action, and settings for screen width/height. WiFi screen replies update those settings and show the received dimensions. `ReportEncoder` encodes center as the protocol-v2 top-left slam followed by half-screen movement for BLE/HID.

The flick detector now fires on the threshold falling edge only when the pulse duration is at most 220 ms, has a 600 ms refractory period, and is invoked only in `mode === 'hold'` while the pad is untouched. A 500 ms strong-turn regression test does not fire.

## Decisions and remaining risks

- BLE uses the library's bundled plugin because it supports the current package and adds the required native permissions without the incompatible old community plugin.
- HID uses report ID 1 for the mouse payload and report ID 2 for keyboard arrows; the five-byte JS encoder remains shared with the dongle path.
- BLE dongle and Android HID have not been paired or exercised on physical hardware in this session.
- The APK has not been installed on a phone, per task rules. OEM HID support, Bluetooth pairing behavior, pointer acceleration during center, and actual ESP32 USB enumeration remain unverified.
- The iOS build emitted upstream Swift deprecation/sendability warnings from Expo/RxSwift/BLE dependencies; the Release build still completed successfully.

## Owner device checklist

### iPhone

1. Choose WiFi or BLE dongle and connect.
2. Tap `คาลิเบต`, place the phone still on a table for two seconds, then perform the left-edge/right-edge taps and finish with `กลางจอ`.
3. In `hold` mode, verify cursor movement requires touching the pad.
4. In `always` mode, turn the phone quickly and confirm it does not change slides; enable flick in `hold` mode and verify the return swing does not trigger the opposite slide.

### Android

1. Pair the phone with the Mac/TV first, choose `Bluetooth HID`, and tap connect. If registration fails, use the BLE dongle path.
2. Verify movement, left/right click, wheel, arrow-key slides, disconnect/reconnect, calibration, and `กลางจอ`.

### Dongle

1. Flash using the exact command in `dongle/README.md`; hold BOOT, tap RESET, then release BOOT.
2. Use the USB-OTG port, scan for `AirMouse-Dongle`, and verify move/click/scroll/slide, drag release after disconnect, and center behavior.
