# AirMouse v3 spec: design system, protocol, calibration

Owner of this file: yasuri. Binding for the Mac app (`desktop/mac/`) and the iPhone app (`app/`). If something here is impossible, implement the closest thing and write why in your report; do not silently change the protocol.

## 0. Product

AirMouse turns an iPhone into an air mouse for a Mac (like an LG Magic Remote): turn the phone, the cursor follows. Two apps:
- **AirMouse for Mac** (native SwiftUI, `desktop/mac/`): receives over Wi-Fi, moves the real cursor, shows the calibration overlay.
- **AirMouse for iPhone** (Expo SDK 58 / RN 0.88, `app/`): reads the gyroscope, sends motion, runs the calibration flow.

All UI copy is **English**. Tone: short, friendly, Apple-like ("Hold Your iPhone to the Screen", "You're All Set").

## 1. Design system ("Apple, minimal, colourful, readable")

Follow Apple HIG for iOS 27 / macOS 27 (Liquid Glass era: translucent materials, rounded, depth, springy motion). Light and dark mode both, following the system.

**Type**
- Apple system font only: SF Pro (Text/Display picked automatically). Numbers and big status values: SF Pro Rounded (`ui-rounded` on iOS RN, `.rounded` design in SwiftUI).
- Scale (pt): Large Title 34 bold · Title 28 bold · Title2 22 semibold · Headline 17 semibold · Body 17 · Callout 16 · Subhead 15 · Footnote 13 · Caption 12. Minimum 13 pt for anything the user must read. Respect Dynamic Type where cheap.

**Colour**
- Neutrals = system colours (`systemBackground`, `secondarySystemBackground`, `label`, `secondaryLabel`, separators). Do not invent greys.
- Brand gradient "Aurora" (used sparingly: primary buttons, active touch surface glow, calibration glow, app icon):
  `#0A84FF` (blue) -> `#5E5CE6` (indigo) -> `#BF5AF2` (purple), 135°.
- Calibration glow: `#64D2FF` (cyan) core with blue outer glow, like the Apple TV colour-balance screen.
- Semantic: success `#30D158`, warning `#FF9F0A`, error `#FF453A`.
- Contrast: text >= 4.5:1 on its background in both modes.

**Shape and layout**
- Corner radius: cards 22, buttons 14 (or capsule), small chips capsule. Use continuous corners.
- Spacing grid 4; screen margins 20 (iOS) / 24 (Mac). Generous whitespace, one primary action per screen.
- Materials: cards on `.regularMaterial` / blur where it helps (Mac window, iOS overlays); otherwise grouped backgrounds.
- Icons: SF Symbols (`expo-symbols` on iOS, `Image(systemName:)` on Mac). Suggested: `cursorarrow.rays` (brand), `laptopcomputer`, `iphone`, `wifi`, `qrcode.viewfinder`, `scope` (calibrate), `dot.circle.and.cursorarrow` (center), `hand.tap`, `gearshape`, `waveform.path.ecg` (sensors), `checkmark.circle.fill`, `exclamationmark.triangle.fill`, `lock.shield` (Accessibility).

**Motion**
- Springs (response ~0.35-0.5, damping ~0.8). No linear tweens except progress.
- Haptics on iPhone for: connect, click, step complete, success (notification success), error.
- Respect Reduce Motion: replace movement with fades.

## 2. Discovery and connection

- Mac advertises Bonjour `_airmouse._tcp` (service name = the Mac's name, e.g. "Nattakit's MacBook Pro") on its WebSocket port (default **8765**, fall back to the next free port if busy and advertise the real one).
- Mac shows a QR code with `airmouse://connect?host=<ip>&port=<port>&name=<urlencoded mac name>`.
- iPhone connects by (1) tapping a Mac in "Nearby Macs" (Bonjour browse), (2) scanning the QR code, or (3) typing an address. It remembers the last Mac and auto-reconnects on launch.
- iOS needs `NSLocalNetworkUsageDescription` and `NSBonjourServices = ["_airmouse._tcp"]`; camera usage string for QR.

## 2. First-run onboarding (owner requirement, both apps)

Order on first launch: **Welcome -> Get the other app -> Permissions stepper (2a) -> app -> guided tour**. Everything happens inside the app's own window/screen (Mac: the single main window, full-width pages before the sidebar UI appears; iPhone: full-screen pages). Page dots + Back/Continue; "Skip" only on the tour.

1. **Welcome / What is AirMouse** (1-2 pages): infographic-style hero: phone -> waves -> Mac cursor, with 3 short value points ("Point to move", "Tap to click", "Works over Wi-Fi or Bluetooth"), and a "How it works" strip: Gyroscope -> Smoothing (One Euro filter) -> Cursor. Use the Codex illustrations from `assets-gen/` when available (`illustrations/hero-pointing.png`, `infographics/how-it-works.png`); until then a code-drawn vector version behind a swappable `Illustration` component.
2. **Get the other app**: Mac shows "Get AirMouse on your iPhone" (phone mock-up + short steps; the iPhone app is currently side-loaded, so text: "Install AirMouse on your iPhone, then open it." with a placeholder QR/link slot for a future download page). iPhone shows "Get AirMouse for Mac" (Mac mock-up + "Open AirMouse on your Mac. It shows a QR code to pair."). A "I already have it" button continues.
3. **Permissions** stepper (section 2a).
4. **App** (Mac: Home in the sidebar window; iPhone: Connect).
5. **Guided tour** (coach marks), shown once after the first successful arrival in the app, replayable from Settings / About ("Show Tour"): dim the UI, cut out a rounded spotlight around one element at a time, a callout bubble with title + one sentence + "Next" (step x of n) + "Skip Tour". Spring animation between targets. Measure target frames at runtime (SwiftUI `anchorPreference`/`GeometryReader`; RN `measureInWindow`).
   - Mac tour: status card -> Pair iPhone (QR) -> Calibrate button -> Center Cursor -> Permissions sidebar row -> menu bar hint (text only).
   - iPhone tour (on Remote, after first connect): status pill -> touch pad ("Hold to point, tap to click") -> scroll strip -> Left/Right buttons -> Center -> Calibrate -> Settings tab.
   - Tour/onboarding state is pure logic (step list, next/skip/done, persisted flag) with tests.

## 2a. Permission setup stepper (owner requirement, both apps)

First launch shows a **Setup** flow (also reachable later from Settings / the Mac window "Setup…"), one step per permission, in this order. Each step: SF Symbol in a coloured circle, title, one-line *why*, a primary button that triggers the system prompt or opens the exact Settings pane, and a **live status** that turns into a green check when granted (poll every ~1.5 s while the step is visible and on app re-activation). A left/top progress indicator (step dots or a vertical checklist). "Continue" enables when granted; "Skip for now" is available for non-essential ones. The main screen shows a compact warning row for any permission still missing, which reopens the step.

**Mac**
| Step | Check | Grant action |
|---|---|---|
| Accessibility (required: moves the pointer) | `AXIsProcessTrusted()` | `AXIsProcessTrustedWithOptions(prompt)` + open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` |
| Bluetooth (optional: Bluetooth connection) | `CBManager.authorization` (+ `CBPeripheralManager.state` == poweredOn) | create the peripheral manager to trigger the prompt; denied -> open `...Privacy_Bluetooth` |
| Local Network (required for Wi-Fi) | no direct API: treat as granted when our own Bonjour service resolves via `NWBrowser` / the listener reaches `.ready` and a loopback-to-LAN-IP test connection succeeds; denied = browser `.waiting` with policy denial | start the listener/browser to trigger the prompt; open `...Privacy_LocalNetwork` (falls back to the Privacy pane) |
| Firewall (info) | `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate` and `--getappblocked <app path>` (no sudo needed for reads) | if on and the app is blocked: explain + open `x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall` |

**iPhone**
| Step | Check | Grant action |
|---|---|---|
| Local Network (required for Wi-Fi) | Bonjour browse result: any service found or browser state ready = granted; `NWBrowser` failed/waiting with `kDNSServiceErr_PolicyDenied` = denied | start a browse to trigger the prompt; denied -> `Linking.openSettings()` |
| Bluetooth (optional) | ble-plx `state()` / `CBManager.authorization` | lazy-create BleManager to trigger; denied -> open Settings |
| Camera (optional, for QR) | `expo-camera` `getCameraPermissionsAsync` | `requestCameraPermissionsAsync`; denied -> open Settings |
| Motion sensors | gyroscope `isAvailableAsync` + receiving samples (no permission needed on iOS for raw gyro; show as an automatic green check, educational) | — |

## 2b. Connection options (owner requirement: the user must be able to choose)

The iPhone "Connect" screen offers, in this order:

| Option | How | Needs |
|---|---|---|
| **Nearby (Wi-Fi)** | Bonjour list, tap a Mac | same Wi-Fi |
| **Scan QR Code** | QR shown in the Mac app | same Wi-Fi |
| **Enter IP Address** | host + port fields | same Wi-Fi / hotspot |
| **Bluetooth** | scan for Macs running AirMouse, tap one | Bluetooth on both, **no Wi-Fi needed** |

**MVP scope (owner, 2026-11-04): iPhone + Mac app only.** The dongle (`ble.ts`) and Android HID (`hid.ts`) stay in the code base but are hidden from the UI this round. TVs / other computers will get their own receiver app later.

**Bluetooth to the Mac app (new).** The Mac app is a BLE *peripheral* (`CBPeripheralManager`) and the iPhone a *central* (`react-native-ble-plx`, already installed). This is a custom GATT service, so iOS allows it (unlike HID).
- Service `7b0e0010-7d6b-4d9c-9a31-4a2d2f9e0101`, advertised local name `AirMouse-<short Mac name>` (max ~20 bytes; also put the service UUID in the advertisement so the phone can filter).
- Characteristic **rx** `7b0e0011-7d6b-4d9c-9a31-4a2d2f9e0101`: write + write-without-response. Phone -> Mac. Value = one UTF-8 protocol-v3 JSON message per write (same messages as WebSocket). `move` uses write-without-response; everything else write-with-response. Keep messages under the negotiated MTU (use short JSON, no whitespace); coalesce moves to at most one write per gyro tick.
- Characteristic **tx** `7b0e0012-7d6b-4d9c-9a31-4a2d2f9e0101`: notify. Mac -> phone, same JSON (`screen`, `calib`). The Mac sends `screen` right after the phone subscribes (the phone still sends `hello` first via rx; Mac replies on tx).
- Mac Info.plist needs `NSBluetoothAlwaysUsageDescription`. The Mac window shows a "Bluetooth" status row (Off / Advertising / Connected to <phone>).
- Wi-Fi and Bluetooth can both be enabled on the Mac at once; the Mac handles messages from either the same way.

## 3. Protocol v3 (JSON over WebSocket, one object per text frame)

Unknown `t` values and unknown fields must be ignored by both sides. Integers are screen points (macOS logical points), +x right, +y down.

### iPhone -> Mac
| Message | Meaning |
|---|---|
| `{t:'hello', v:3, app:'airmouse', device:{name, model, wMm, hMm}}` | first message. `wMm/hMm` = phone body size in millimetres (iPhone 15: 71.6 x 147.6; lookup by model, fallback 71.5 x 147.5) |
| `{t:'move', dx, dy}` | relative move in points; **may be fractional** (ints still valid). The Mac paces moves to the display refresh (section 5, "Pointer pacing") |
| `{t:'button', b:'left'\|'right', down:bool}` | press / release |
| `{t:'scroll', dy}` | notches, positive = scroll down |
| `{t:'key', k:'left'\|'right'\|'up'\|'down'\|'backspace'\|'enter'\|'tab'\|'escape'\|'space'}` | key tap (down + up). Virtual keys 123, 124, 126, 125, 51, 36, 48, 53, 49. Unknown `k` = ignored |
| `{t:'text', s:string}` | type a unicode string into the focused app (CGEvent `keyboardSetUnicodeString`, chunks of <= 20 UTF-16 units, never splitting a surrogate pair; key down + up per chunk). Empty = ignored; the Mac cuts `s` at 2000 characters |
| `{t:'practice', step:'start'\|'stop'}` | open (or restart) / close Click Practice on the Mac |
| `{t:'center'}` | warp cursor to the centre of the main display |
| `{t:'calib', step:'start'}` | show the calibration overlay (place step) |
| `{t:'calib', step:'place', progress:0..1, still:bool}` | ~10 Hz while the phone is held to the screen. `still=false` resets the ring |
| `{t:'calib', step:'placed'}` | bias captured; Mac plays success pulse on the outline and warps the cursor to the screen centre. **From now on the Mac drops `move` from this phone until `pointed` `center`** (also cleared by `verify`, `done`, `cancel`, `start`, disconnect), so lifting the phone cannot move the cursor |
| `{t:'calib', step:'point', target:'center'\|'tl'\|'tr'\|'br'\|'bl'}` | v3 (spec 4b): sent in that order; Mac shows only that target. For `center` (first entry **and Redo**) the Mac warps the cursor to the screen centre and blocks this phone's moves until `pointed` `center`. `'left'\|'right'` still accepted from older phones |
| `{t:'calib', step:'pointed', target}` | user tapped; Mac shows a green check on the dot. For `center`: the Mac also warps the cursor to the screen centre and accepts moves again, so the real cursor follows during `tl`/`tr`/`br`/`bl` (the phone sends moves from then on; the measurement is gyro-based, unaffected) |
| `{t:'calib', step:'verify'}` | v3: pointing done; moves allowed again; Mac shows all 5 dots lighting while the real cursor is within 40 pt |
| `{t:'calib', step:'done', sensitivity}` | Mac shows "You're All Set", fades the overlay after ~1.2 s, cursor to centre |
| `{t:'calib', step:'cancel'}` | close the overlay |

### Mac -> iPhone
| Message | Meaning |
|---|---|
| `{t:'screen', w, h, scale, wMm, hMm, name}` | reply to `hello`, and when the main display changes. `wMm/hMm` from `CGDisplayScreenSize` |
| `{t:'calib', step:'request'}` | user clicked "Calibrate" on the Mac: iPhone opens its calibration flow |
| `{t:'calib', step:'cancel'}` | user pressed Esc / Cancel on the Mac overlay |
| `{t:'calib', step:'hit', target}` | v3 verify: the real cursor reached that dot for the first time this run (once per target) |
| `{t:'focus', editable:bool}` | the system-wide focused UI element became (non-)editable. Sent once right after `hello` (after `screen`), then only on change. AX poll every 300 ms on the Mac, only while a phone is connected and Accessibility is granted (no grant = never sent; treat as `false`). Editable = role AXTextField / AXTextArea / AXComboBox / AXSearchField, or AXEditableAncestor present, or AXValue settable (except known non-text controls such as sliders, checkboxes, pop-ups) |
| `{t:'practice', step:'running', hits, total}` | Click Practice is on screen: sent on start (0, 0) and after every hit. `hits` = targets hit, `total` = all clicks (hits + misses) |
| `{t:'practice', step:'result', hits, total, ms}` | finished all 10 targets. `hits` = 10, `total` = all clicks, `ms` = average time per target in milliseconds (integer) |
| `{t:'practice', step:'stop'}` | Click Practice closed early on the Mac (Esc / Cancel). Not sent after `result`, nor in reply to the phone's own `stop` |

### Click Practice (Mac)
Fullscreen overlay on the main display (same level and look as calibration) that **takes mouse clicks**. 10 cyan glowing round targets, one at a time, at random positions inside 10% margins; diameter 64 pt shrinking linearly to 44 pt on the last one. A click inside = hit (pop, next target); outside = miss (small red ripple). Progress "n of 10" at the top; result card (hits/clicks, accuracy, average time per target, "Try Again", "Done"). Esc / Cancel closes it. Start: Home or Calibration page "Practice Clicking", Pointer menu (⇧⌘P), menu bar, or the phone message. Starting calibration closes practice.

### Calibration geometry (both sides must agree)
- Outline: a rounded rectangle the **physical size of the phone** (`wMm x hMm` converted with points-per-mm = `w / wMm` of the display), centred on the main display, corner radius = 12 mm physical.
- v3 targets (display-local points, top-left origin): `center` = `(0.5w, 0.5h)`; corners inset 8%: `tl` = `(0.08w, 0.08h)`, `tr` = `(0.92w, 0.08h)`, `br` = `(0.92w, 0.92h)`, `bl` = `(0.08w, 0.92h)`. Verify hit radius 40 pt.
- Legacy targets: dots at `(0.1 * w, 0.5 * h)` (left) and `(0.9 * w, 0.5 * h)` (right). Distance = `0.8 * w`.
- Sensitivity = `0.8 * w / |yaw angle between the two taps|` (points per radian), clamped to the app's range.

## 4. Calibration flow (the showcase)

Reference: Apple TV "colour balance" — the TV shows a glowing phone-shaped outline on a dark animated background with instructions on the left; the person holds the iPhone against the screen inside the outline; the phone shows a small illustration of the same step.

| Step | Mac overlay (fullscreen on the main display, above everything, Esc = cancel) | iPhone |
|---|---|---|
| 1 Start | Fade in: near-black background with slow drifting blue/cyan particles (subtle, 30-60 fps, cheap). Left column: step number in a ring, title "Hold Your iPhone to the Screen", body "Turn your iPhone so the screen faces you and hold it flat against the display, inside the outline." Centre: glowing cyan phone outline at real size, gently breathing. | Full-screen sheet. Animated mock-up: a mini display with the glowing outline, an iPhone slides in from below and settles inside it (loop). Title "Hold Your iPhone to the Screen", body as Mac, "Cancel" button. |
| 1 Hold | The outline's stroke fills clockwise with progress; if `still=false` it drains back. | Stillness detection: gyro magnitude below threshold (after bias-free check) for 2.0 s → progress ring around the mock-up; sends `place` at ~10 Hz. When 2 s of still samples are collected, compute gyro bias (existing `calibrateBias`). |
| 1 Done | Outline flashes white then success green tick; cursor warps to outline centre. | Haptic success. "Great." then auto-advance after 0.8 s. |
| 2 Point left | Outline fades. Pulsing target dot at left with label "Point here". | "Point at the Left Dot", illustration: phone held like a remote, arrow to the left; "Tap anywhere when you're pointing at it." Tap = `pointed`; starts yaw integration from this moment. |
| 3 Point right | Left dot shows hit ring, right dot appears. | "Now Point at the Right Dot". Tap = end of integration; compute sensitivity (existing `integrateYaw` / `sensitivityFromAngle`); reject < 0.1 rad with "Try a bigger turn". |
| 4 Done | "You're All Set" with a checkmark, fades after ~1.2 s. | "You're All Set" + summary (sensitivity value, bias OK), "Done". Settings saved. |

### 4a. Calibration v2 (owner feedback 2026-11-04, supersedes step 1 above where they differ)

Problems seen on the real devices: step 1 completed while the phone was not on the screen (stillness alone is not proof); after "You're All Set" the cursor did not move; sensitivity hit the 4000 cap.

1. **Placement must be detected, not assumed.** Like Apple TV, the phone's **screen faces the display** (front camera / proximity sensor against the glass). Copy: "Turn Your iPhone Around" / "Hold it flat against the screen, inside the outline, with the display facing the screen." Placement = all of:
   - **proximity sensor near** (iOS `UIDevice.isProximityMonitoringEnabled` + `proximityState`, via the local `airmouse-discovery` module or a new tiny module; the phone screen turns off while near — that is expected, guidance continues on the Mac overlay + haptics),
   - **upright against a vertical-ish display**: accelerometer gravity mostly along the device Y axis (|ay| > 0.75 g, |az| < 0.6 g) — rejects a phone lying on the desk,
   - **still** (existing detector) for 2.0 s.
   Progress only accumulates while all three hold; the phone sends `place` with `still=false` the moment any fails (Mac ring drains). States sent to the Mac via a new optional field: `{t:'calib', step:'place', progress, still, near:bool, upright:bool}` so the overlay can say "Move closer to the screen" / "Hold it upright" / "Hold still". Before the phone is near, the phone's own screen shows the animated mock-up and "Bring your iPhone to the screen". When lifted after success, the phone screen shows the next step (it auto-advances on `near == false` after placed).
2. **After "You're All Set" the flow closes itself** after ~1.5 s (or on tap) and returns to Remote with motion resumed; show a small "Calibrated" toast. Guarantee `setPaused(false)` on every exit path (done, cancel, Mac cancel, disconnect, app background) — with a test of the pause bookkeeping.
3. **Sensitivity sanity**: show the measured angle in degrees on the result card; if the result would clamp (angle too small/large), say "That turn looked small — try again, pointing right at each dot" and offer Retry instead of silently saving the cap.
4. **Diagnostics** (to debug on real devices): iPhone Settings > Diagnostics: connection kind/state, paused, touching, gyro Hz, messages sent per type (live), last dx/dy. Mac About > Diagnostics: messages received per type per peer (live), last move time. Both cheap, always available.

### 4b. Calibration v3: four corners (owner feedback 2026-11-04, replaces left/right pointing)

Problem: lifting the phone off the glass after `placed` moved the cursor and spoiled calibration.
1. `place` / `placed` as before. On `placed` the Mac warps the cursor to the screen centre and ignores `move` from that phone until `pointed` `center` (guard on the Mac in addition to the phone not sending moves).
2. Pointing: phone sends `point` with `center`, `tl`, `tr`, `br`, `bl` in order, then `pointed` for each tap. Mac shows only the current target (same glowing dot), a 5-dot progress row, title "Point at the Centre" / "Point at the Top-Left Corner" / "Top-Right Corner" / "Bottom-Right Corner" / "Bottom-Left Corner", subtitle "Aim, then tap your iPhone." `pointed` = green check. On `point` `center` (first time or Redo) the Mac warps the cursor to the centre and blocks moves; on `pointed` `center` the Mac warps the cursor to the screen centre again and stops blocking moves: the phone sends moves from then on and the real cursor follows live during the four corners (live feedback; the measurement is gyro-based, so cursor motion does not affect it).
3. Verify: phone sends `verify`; moves resume. Title "Check Your Pointer", subtitle "Point at each dot. They light up when the cursor touches them." All 5 dots shown; each is green while the cursor (Mac polls `NSEvent.mouseLocation` ~30 Hz) is within 40 pt; the Mac sends `{t:'calib', step:'hit', target}` the first time each lights. A "n of 5 reached" counter sits under the subtitle.
4. `done` / `cancel` as before. The Mac result card adds "Your pointer reached n of 5 dots" when a verify step ran.

5. **Calibration v3: centre + 4 corners (owner feedback 2026-11-04, supersedes steps 2-4 above).** Lifting the phone after placement must not move the cursor: motion stays paused from `start` until the **centre tap**. After `pointed center` (the Mac warps the cursor to the centre) the phone sends live moves with the clutch forced on and the saved settings while the user aims at tl/tr/br/bl, so they can see where they point; the corner angles are still measured by gyro integration.
   - Steps: place (unchanged) -> lift -> point at `center`, tap -> `tl`, tap -> `tr`, tap -> `br`, tap -> `bl`, tap. The phone sends `{t:'calib', step:'point', target}` when each target starts and `{t:'calib', step:'pointed', target}` on each tap (`target` = `center|tl|tr|br|bl`). Phone shows 5 progress dots + the target name ("Top Left · 2 of 5").
   - Targets: centre `(0.5w, 0.5h)`; corners inset 8 %: tl `(0.08w, 0.08h)`, tr `(0.92w, 0.08h)`, br `(0.92w, 0.92h)`, bl `(0.08w, 0.92h)`.
   - Yaw and pitch (bias-corrected, trapezoid) integrate from the centre tap; each corner tap records both angles. `sensX = 0.84·w / mean(|yaw_tr − yaw_tl|, |yaw_br − yaw_bl|)`, `sensY = 0.84·h / mean(|pitch_bl − pitch_tl|, |pitch_br − pitch_tr|)`. Each axis keeps the clamp/retry rule of 4a.3 (retry restarts at the centre). Code: `motion/calibration.ts` `AngleIntegrator`, `evaluateCorners`.
   - **Verify**: after the 5th tap the phone sends `{t:'calib', step:'verify'}` and points live with the new (unsaved) speed, clutch forced on (no hold). The Mac shows the 5 dots and sends `{t:'calib', step:'hit', target}` (Mac -> iPhone) when the cursor touches each; the phone ticks them off. Live "Speed" slider (scales X and Y, keeps the ratio). "Done" sends `{t:'calib', step:'done', sensitivity, sensitivityY}`, saves, closes, toast "Calibrated". "Redo" goes back to the centre.
   - Engine: `MotionSettings.sensitivityY` (vertical; migrated = `sensitivity` for old settings) and `acceleration` 0..1 (default 0.4): velocity × `1 + acceleration · min(|ω| / 1.5, 2)`, ω = filtered angular speed in rad/s (gain 1 at rest, so slow aiming is unchanged). Settings > Pointer: Speed scales both axes keeping the ratio; "Acceleration" slider (Off at 0).
   - After connecting, if this display (`name|w x h` from `screen`) was never calibrated on this phone, a centred glass popup over a dimmed backdrop appears right after the connection opens: "Calibrate for Accurate Pointing" (Hold iPhone against the screen / Point at 5 dots / Check and done; "Start Calibration", "Later"). Only v3 (5-point) calibrations count (`settings.calibratedV3`; older 2-dot results are ignored). It comes back after a cancelled calibration; "Later" hides it for the session.

If the Mac is not connected, iPhone calibration still works (bias + sensitivity from the screen size in Settings) but shows "Connect to a Mac to see the guide on screen".

## 5. Mac app (desktop/mac/)

- macOS 27 SDK, Swift 6, SwiftUI. Built **headlessly** with SwiftPM (`swift build -c release`) + a script that assembles `AirMouse.app` (Info.plist, icon `.icns`, resources) and signs it with the stable identity `Apple Development: nattakit982547@gmail.com (YYXH3GUSWN)` (TCC Accessibility is tied to the signature: ad-hoc signing would force re-granting after every build). Pure logic in a library target with `swift test`.
- Bundle id `com.nattakit.airmouse.mac`, name "AirMouse", `LSUIElement` false (normal Dock app) + a MenuBarExtra.
- Networking: `Network.framework` `NWListener` with `NWProtocolWebSocket`, Bonjour via `listener.service`. No third-party deps.
- Pointer pacing (owner feedback 2026-11-04, "moves, stops, moves, stops"): `move` deltas (fractional) accumulate in `pending`; a display-synced timer (`NSScreen.displayLink`, main display refresh, 120 Hz on ProMotion) emits `pending * k` per frame with `k = 1 - 0.55^(dt * 120)` (0.45 at 120 Hz, same time constant at 60 Hz) and keeps the rest; when |pending| < 0.05 pt it emits all. Sub-pixel cursor position kept as doubles, clamped to the displays; re-synced if something else moved the cursor. While a button is held the paced events are `leftMouseDragged` / `rightMouseDragged`. The timer pauses when idle. Pure logic: `MotionPacer` (AirMouseCore). Gap bridging (AWDL / Wi-Fi spikes of ~100-300 ms): when no move arrives for longer than 1.5x the usual interval (and more than one frame) while the pointer is moving, it glides on at the recent velocity decaying linearly to 0 over 60 ms (once per received move). The glided distance is a debt: late packets repay it first (no overshoot); if nothing arrives within 250 ms it is paced back, so total output = total input. Diagnostics also count move gaps of 50 ms-1 s in the last minute, with the tip "If the pointer hitches every few seconds, turn off AirDrop / Handoff, or use Bluetooth." WebSocket listener TCP uses `noDelay = true` (no Nagle batching). About > Diagnostics shows move inter-arrival mean/max (ms, last 2 s) per peer and the pacer frame rate.
- Cursor: `CGEvent` mouse moved / down / up / drag (when a button is held, moves must be `.leftMouseDragged`), scroll wheel events (`CGEvent(scrollWheelEvent2Source:...)`), arrow keys via `CGEvent(keyboardEventSource:virtualKey:keyDown:)`; `center` uses `CGWarpMouseCursorPosition` + `CGAssociateMouseAndMouseCursorPosition(1)`. Clamp to the union of displays.
- Accessibility: `AXIsProcessTrusted()`; if false, a clear card "Allow AirMouse to control your pointer" + "Open Settings" (`AXIsProcessTrustedWithOptions` prompt + `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`), re-check every 2 s.
- Main window (~400 x 600, unified, material background): brand header (icon + "AirMouse"), status card (dot + "Waiting for your iPhone…" / "Connected to Ghost" + msg rate), pairing card (QR + "Scan with AirMouse on your iPhone" + IP:port small, copy button), Accessibility card when needed, buttons "Calibrate" (prominent, Aurora) and "Center Cursor". Footer: port, version.
- MenuBarExtra: status line, Calibrate…, Center Cursor, Show AirMouse, Quit.
- Calibration overlay per section 4: borderless `NSWindow`/`NSPanel` at `.screenSaver` level on the main display, `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary]`, ignores mouse except an "Cancel" button + Esc key.

## 6. iPhone app (app/)

- Keep the engine/transport layering. Replace all Thai copy with English. Rebuild screens to the design system.
- Tabs: **Remote**, **Sensors**, **Settings** (native-feeling tab bar with SF Symbols; blur background).
- Connect screen (shown when not connected; also from the status pill): large title "Connect to a Mac", "Nearby" list (Bonjour), "Scan QR Code", "Enter Address".
- Remote: top status pill (Mac name + green dot; tap to change Mac), large touch surface ("Hold to Point" / while held: Aurora glow + "Pointing"), quick tap = click, scroll strip, Left/Right click buttons, a row with Center, Calibrate, Prev/Next slide.
- Sensors: live gyro/accel charts restyled (rounded cards, system colours for axes), short English explanation (it is a sensor course).
- Settings: inset grouped list: Pointer (mode Hold/Always, sensitivity slider, smoothing, dead zone), Gestures (flick slides), Invert axes, Screen size (auto from Mac), Calibration (run, reset), Connection (Wi-Fi default; BLE dongle / Bluetooth HID under "Experimental"), About.
- Calibration full-screen flow per section 4.
- Remote also has: a "Hold to Point" / "Always On" segmented toggle under the status pill (same persisted setting as Settings > Pointer > Mode; in Always On a touch on the pad pauses pointing); a round glass **Practice** button (left of the pill) that sends `{t:'practice', step:'start'|'stop'}`, a banner "Practice running on Mac: point and tap to click" on `practice running`, and a result toast (hits/total, average ms) on `practice result`; a round glass **Keyboard** button (right of the pill).
- Keyboard panel: opens on Mac `{t:'focus', editable:true}` (switches to Remote unless calibration/setup is open) or the Keyboard button. A hidden, auto-focused TextInput keeps the iOS keyboard up; its value is diffed (caret at end) and sent as `{t:'text', s}` batched ~50 ms, deletions / empty-box Backspace as `{t:'key', k:'backspace'}`, Return as `key enter`. Special-key row: esc, tab, arrows, return; Done dismisses. `focus editable:false` closes it only if nothing was typed in the last 2 s. The pad shrinks above the keyboard so pointing keeps working. Keys: left, right, up, down, backspace, enter, tab, escape, space (BLE/HID report paths drop everything but left/right).
- Calibration is the v3 flow of 4a.5 (place, 5 taps, verify with live speed). A centred "Calibrate for Accurate Pointing" popup appears after connecting to a display without a v3 calibration; Settings > Pointer has Speed (both axes, ratio kept) and Acceleration.
- Multi-touch: the pad and the Left/Right click buttons use raw touch events (per-finger identifiers, `src/ui/touches.ts`), not the single-owner responder, so hold the pad with one finger and press Left with another = drag.
- Must keep working: gyro pointing, clutch, flick, existing tests. iOS is the target device (iPhone 15, iOS 27); Android must still compile but is not the focus.
