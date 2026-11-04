<div align="center">

<img src="docs/images/icon.png" width="120" alt="AirMouse icon">

# AirMouse

**Point your iPhone at your Mac. The cursor follows.**

An air mouse built from the sensors already inside your phone, like an LG Magic Remote.

</div>

<p align="center">
  <img src="docs/images/desktop-hero.jpg" alt="AirMouse hero" width="900">
</p>

## What is AirMouse

AirMouse turns an iPhone into an air mouse for a Mac. Hold the phone, point it at the screen, and the cursor follows your hand. The phone reads its gyroscope, filters the motion and streams small movement messages over Wi-Fi or Bluetooth LE to a native Mac app, which moves the real cursor.

It is mini project 1 (sensor app) of the Mobile App course, TCT, KMUTNB.

## Features

- **5-point calibration**, Apple TV style: place the phone on the screen, then point at the centre and the 4 corners.
- **Keyboard typing**: the phone keyboard pops up when a text field is focused on the Mac.
- **Click Practice**: a small target game on the Mac that measures your hits and speed.
- **Hold to Point / Always On** pointing modes.
- **Two-finger drag** and **smooth trackpad-style scrolling** with momentum.
- **Smooth 120 Hz cursor pacer** on the Mac, so Wi-Fi bursts do not make the cursor stutter.
- **Wi-Fi (Bonjour + WebSocket) or Bluetooth LE** connection, plus QR pairing.
- **Onboarding** with a permission stepper, and a **How It Works** explainer.

> **Screenshots:** the Mac app and calibration overlay are shown below. iPhone screenshots are not included yet, because the iPhone app is installed from Xcode onto a real device.

<table>
  <tr>
    <td align="center"><img src="docs/images/window-home-light.jpg" alt="Home, light"><br><sub>Mac app, light</sub></td>
    <td align="center"><img src="docs/images/window-home-dark.jpg" alt="Home, dark"><br><sub>Mac app, dark</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/window-onboarding-1-welcome-light.jpg" alt="Onboarding welcome"><br><sub>Onboarding: welcome</sub></td>
    <td align="center"><img src="docs/images/window-onboarding-2-howItWorks-light.jpg" alt="Onboarding how it works"><br><sub>Onboarding: how it works</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/window-onboarding-3-getIPhone-light.jpg" alt="Onboarding get iPhone app"><br><sub>Onboarding: get the iPhone app</sub></td>
    <td align="center"><img src="docs/images/window-onboarding-4-permissions-light.jpg" alt="Onboarding permissions"><br><sub>Onboarding: permission stepper</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/window-pair-light.jpg" alt="Pairing"><br><sub>Pairing with a QR code</sub></td>
    <td align="center"><img src="docs/images/window-calibration-light.jpg" alt="Calibration"><br><sub>Calibration status</sub></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><img src="docs/images/practice-2-running.jpg" alt="Click Practice" width="60%"><br><sub>Click Practice running on the Mac</sub></td>
  </tr>
</table>

## Sensors it uses

| | Sensor | Role |
|---|---|---|
| <img src="docs/images/sensors/gyroscope.jpg" width="90" alt="Gyroscope"> | **Gyroscope** (main, 100 Hz) | Pointing: turning left/right moves the cursor sideways, tilting moves it up/down. |
| <img src="docs/images/sensors/accelerometer.jpg" width="90" alt="Accelerometer"> | **Accelerometer** | Measures gravity, used during calibration to check the phone is upright. |
| <img src="docs/images/sensors/proximity.jpg" width="90" alt="Proximity"> | **Proximity** | Confirms the phone is really against the screen, so calibration cannot start by mistake. |
| <img src="docs/images/sensors/touchscreen.jpg" width="90" alt="Touchscreen"> | **Touchscreen** | Hold to point, tap to click, two-finger drag and scroll, keyboard. |
| <img src="docs/images/sensors/camera.jpg" width="90" alt="Camera"> | Camera | Scans the QR code for pairing. |
| <img src="docs/images/sensors/haptics.jpg" width="90" alt="Haptics"> | Haptics | Vibration feedback for clicks and calibration. |

## How it works

```mermaid
flowchart LR
  A[Gyroscope<br/>100 Hz] --> B[Bias removal]
  B --> C[One Euro filter]
  C --> D[Pixels]
  D --> E["JSON move message<br/>Wi-Fi or BLE"]
  E --> F[Mac pacer<br/>120 Hz]
  F --> G[CGEvent<br/>real cursor]
```

1. The gyroscope reports turning speed about 100 times a second.
2. The sensor's small built-in error (bias) is removed, then a **One Euro filter** keeps the cursor steady when the hand shakes but still reacts quickly to fast moves.
3. The speed becomes a small distance in pixels and is sent as a short JSON `move` message.
4. The Mac app receives it and a pacer moves the real cursor with `CGEvent`, smoothed to the display refresh rate.

Everything stays on the local network. Nothing goes to the internet.

<table>
  <tr>
    <td align="center"><img src="docs/images/01-gyro.jpg" alt="Gyro"><br><sub>Gyroscope</sub></td>
    <td align="center"><img src="docs/images/03-direction.jpg" alt="Direction"><br><sub>Direction</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/06-mac-cursor.jpg" alt="Mac cursor"><br><sub>Mac cursor</sub></td>
    <td align="center"><img src="docs/images/07-calibration.jpg" alt="Calibration"><br><sub>Calibration</sub></td>
  </tr>
</table>

<p align="center"><img src="docs/images/how-it-works.jpg" alt="How it works infographic" width="800"></p>

## Calibration

Calibration maps the direction of the phone to the screen. It runs full screen on the Mac, driven from the iPhone:

1. **Place**: lay the phone flat against the screen inside the outline. The accelerometer and proximity sensor confirm it is upright and touching.
2. **Point**: point at the centre, then each of the 4 corners, and tap on the phone.
3. **Verify**: move around with live speed feedback, then finish.

<table>
  <tr>
    <td align="center"><img src="docs/images/overlay-1-place.jpg" alt="Place"><br><sub>1. Place the phone</sub></td>
    <td align="center"><img src="docs/images/overlay-1-hint-1-bring-closer.jpg" alt="Hint"><br><sub>Hint: bring it closer</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/overlay-v3-2-point-1-center.jpg" alt="Point at centre"><br><sub>2. Point at the centre</sub></td>
    <td align="center"><img src="docs/images/overlay-v3-2-point-2-tl.jpg" alt="Point at corner"><br><sub>Then each corner</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/images/overlay-v3-3-verify.jpg" alt="Verify"><br><sub>3. Verify</sub></td>
    <td align="center"><img src="docs/images/overlay-v3-4-done.jpg" alt="Done"><br><sub>Done</sub></td>
  </tr>
</table>

## Project structure

```
app/            iPhone app: Expo / React Native + native Swift modules
  src/            motion engine, transport, screens
  modules/        native modules (Bonjour discovery, HID)
desktop/mac/    Mac app: native SwiftUI (SwiftPM), build.sh, Tests/
desktop/        legacy Python receiver (WiFi only)
dongle/         ESP32-S3 BLE-to-USB dongle (experimental)
tools/          deploy-ios.sh, make-dmg.sh
web/            landing page
docs/           spec-v3.md, presentation-script.md, images/
assets-gen/     generated artwork
```

## Build and run

### Mac app

Requires macOS with Xcode and Swift 6.

```bash
desktop/mac/build.sh                          # builds desktop/mac/dist/AirMouse.app (signed)
open desktop/mac/dist/AirMouse.app
cd desktop/mac && swift test                  # unit tests
tools/make-dmg.sh                             # package into web/downloads/AirMouse.dmg
```

Grant Accessibility permission when asked (System Settings > Privacy & Security > Accessibility). Set `AIRMOUSE_SIGN_IDENTITY` to your own signing identity if needed.

### iPhone app

The iPhone app is installed from Xcode onto a real device (iPhone 15, iOS 27 is the target). Sensors do not work in the simulator.

```bash
cd app && npm install
tools/deploy-ios.sh                           # build and install on a connected iPhone
cd app && npm test && npx tsc --noEmit && npx expo lint
```

The first time, trust the developer in Settings > General > VPN & Device Management and allow Local Network access.

### Connect

Put the iPhone and Mac on the same Wi-Fi (university Wi-Fi often blocks device-to-device traffic, so use a hotspot if needed), then pick the Mac from the Nearby list or scan the QR code. Bluetooth LE is also available.

## Tech stack

- **iPhone:** Expo SDK 58, React Native 0.88, TypeScript, native Swift modules
- **Mac:** Swift 6, SwiftUI, SwiftPM, CGEvent, Bonjour, WebSocket, Core Bluetooth
- **Protocol:** JSON over WebSocket, one object per text frame (see `docs/spec-v3.md`)
- **Filtering:** One Euro filter with gyro bias removal
- **Tests:** Jest / `npm test` (app), `swift test` (Mac)

## Credits

Made by Nattakit · KMUTNB

Mobile App course, TCT, KMUTNB. Mini project 1: sensor app.
