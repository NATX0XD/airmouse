# Task 13: "Sensors AirMouse Uses" pages at the start of How It Works (Mac and iPhone)

You are kasuki (Codex). cwd is `airmouse/`. No git commits. Same design and art style as task 12: Apple-native, plus 3D art like `assets-gen/explainer/`.

## Goal
In the "How AirMouse Works" stepper from task 12, on both Mac and iPhone, add a section **before** the existing 8 pages that shows which iPhone sensors AirMouse uses. Use plain English for non-technical people.

## Content (use this copy, lightly edited if needed)
**Overview page.** Title: "Sensors AirMouse Uses". Subtitle: "No extra hardware. Just what's already inside your iPhone." Show a grid of 4 cards, each with an illustration, a name and one line:
1. **Gyroscope** (the main one): measures how fast your phone turns, 100 times a second. Turning left or right moves the cursor sideways; tilting up or down moves it up or down.
2. **Accelerometer**: feels gravity, so AirMouse knows whether the phone is held upright. Used during calibration to check the phone is flat against the screen.
3. **Proximity sensor**: the sensor next to the front camera that turns the screen off during calls. During calibration it confirms the phone is really touching the monitor, so calibration can't start by mistake.
4. **Touchscreen**: hold the pad to point, tap to click, plus buttons for right click, scrolling and typing.

Then a small "Also used" row: **Camera** (scans the QR code to pair) and **Haptics** (gentle vibrations for feedback).

Optionally, one detail page per sensor: a big illustration plus 2 sentences. On iPhone, add a tiny live reading where it's cheap: the gyroscope already has a live demo, so add the accelerometer tilt too. Read only; don't touch useAirMouse.

## Art (use your image tool)
Generate 6 glossy 3D illustrations in the same style into `assets-gen/explainer/sensors/`:
- `gyroscope.png`: spinning gyro rings around an iPhone
- `accelerometer.png`: iPhone with a gravity arrow or level bubble
- `proximity.png`: iPhone top edge with a sensor beam touching a monitor
- `touchscreen.png`: finger on the glass with a ripple
- `camera.png`: QR scan frame
- `haptics.png`: iPhone with vibration waves

Copy them into the Mac bundle (build.sh) and into `app/assets/illustrations/explainer/sensors/`.

## Constraints
- Don't touch `app/src/transport/`, `app/modules/`, `useAirMouse.ts` or native iOS files.
- Don't deploy to the iPhone. Run `npm test`, `tsc` and `expo lint` only.
- **Mac:** `swift test`, then `./build.sh`. Render previews of the new pages, view them and iterate. Then quit the app, replace /Applications/AirMouse.app and `open` it. Delete any backup copies you create in /Applications.
- tmux rule: never touch `cjm-landing-tmux`. No `tmux kill-server` and no `kill-session -a`.

Print a 3-line summary.
