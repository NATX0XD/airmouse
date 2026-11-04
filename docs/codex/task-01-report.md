# Task 01 report

## Stage A

Built the shared five-byte report encoder, including button state, int8/two's-complement encoding, large-delta splitting, wheel sign conversion, and key press/release reports. Added pure flick detection and wired it to gyro input, haptics, and the Thai settings switch. Added persisted `transport` and `flickSlides` settings and a WiFi/BLE/HID picker. HID is disabled on iOS with the requested Thai explanation. BLE/HID picker entries currently use a safe unavailable transport until their native implementations land.

Gate results:

```text
cd app && npm test                         PASS (16 tests)
cd app && npx tsc --noEmit                 PASS
cd app && npx expo lint                    PASS (no errors)
npx expo export --platform ios --platform android --output-dir <tmp>  PASS
```

Export completed to `/tmp/airmouse-export.a486du`. No generated native folders were changed.

## Stage B

Added `dongle/airmouse_dongle/` firmware, shared UUID header, BLE service/characteristic, report batching, USB mouse/keyboard handling, button release on disconnect, and Thai flashing notes. The firmware uses the Arduino-ESP32 core BLE API and TinyUSB HID APIs.

Blocked: `npx expo install react-native-ble-plx @config-plugins/react-native-ble-plx` failed because the available config plugin version declares peer `expo ^49`, incompatible with this Expo SDK 58 app. Therefore the BLE native transport, app config plugin, prebuild/pod install, Arduino compile, and iOS release gate were not attempted. `arduino-cli` is also not installed on this machine.

## Stage C

Not started because the native transport foundation is blocked and Android HID requires a local Expo module plus Android prebuild. No Android native folder or APK was produced.

## Risks / decisions

- Flick direction follows the existing axis convention: negative gyro Z is right; positive gyro Z is left. Threshold is 4 rad/s and refractory is 600 ms; tune on device.
- BLE report UUIDs are mirrored in `app/src/transport/bleIds.ts` and `dongle/.../uuids.h`.
- The dongle currently uses the key byte as a keyboard arrow tap, while mouse movement remains the first four bytes.
- Native BLE/HID and hardware compatibility remain unverified, especially OEM Bluetooth HID Device support and ESP32-S3 USB mode/FQBN options.

## Owner device checklist

- iPhone: enable flick slides, verify left/right slide direction and that a return swing does not change slide.
- iPhone + ESP32-S3: scan/connect, move, click, scroll, hold/release drag, and verify reconnect releases buttons.
- Android 9+ + Mac: pair Bluetooth HID, verify mouse movement/click/scroll and arrow-key slides.
- Android 9+ + TV: repeat pairing and verify the TV accepts the HID profile.
