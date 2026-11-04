# Task 12: "How AirMouse Works" explainer stepper (Mac and iPhone)

You are kasuki (Codex). cwd is `airmouse/`. No git commits. Design: Apple-native, as in task 10/11. Light/dark, SF Pro, the 3D art style of `assets-gen/mac3d/`.

## Goal
Add a friendly stepper that explains, in **plain English for non-technical people**, how the phone's sensors work and how the data gets to the Mac. Short sentences, no jargon. If a technical word is unavoidable, explain it in brackets, e.g. "gyroscope (a tiny motion sensor)".

## Pages (one idea per page: big illustration, title, 1–2 short sentences, optional small "Fun fact")
1. **Your iPhone feels movement.** Inside your iPhone is a tiny motion sensor called a gyroscope. It notices when you turn or tilt the phone.
2. **It checks 100 times a second.** Every hundredth of a second, AirMouse asks the sensor: "How fast are you turning right now?"
3. **Turning becomes moving.** Turn left or right and the pointer moves sideways. Tilt up or down and it moves up or down.
4. **Smoothing out shaky hands.** Everyone's hands shake a little. AirMouse filters out tiny wobbles, so the pointer stays steady but still follows quick moves.
5. **Sending it to your Mac.** The phone sends small messages ("move 3 dots right") over Wi-Fi or Bluetooth. Nothing leaves your home network.
6. **Your Mac moves the pointer.** The AirMouse app on your Mac receives each message and moves the cursor smoothly at your screen's refresh rate.
7. **Calibration makes it accurate.** By pointing at 5 dots, AirMouse learns how far the cursor should move when you turn, for your screen and your distance.
8. **Touch to point, tap to click.** Hold the touch pad to move, tap to click, and use the buttons for right click and scrolling.

Optional: a small live demo on the iPhone pages 2–3 showing the real gyro values as a moving dot (use the existing gyro listener hook; read only).

## Art
Generate one 3D illustration per page with your image tool into `assets-gen/explainer/` (transparent PNG, same glossy style), and copy them into:
- the Mac bundle via build.sh, the same way the existing Illustrations are copied;
- `app/assets/illustrations/explainer/`, loaded with `require`.

## Where it appears
- **Mac:** a new step in onboarding after Welcome ("How It Works", replacing the current crude infographic page), plus About → "How AirMouse Works" to reopen it.
- **iPhone:** a new step in WelcomeFlow (with Skip), plus Settings → Help → "How AirMouse Works".
- Stepper UI: step dots, Back/Next, swipe on iPhone, cross-fade or slide animation that respects Reduce Motion, and Done on the last page.

## Constraints
- Another agent is editing the iPhone BLE code. **Don't touch** `app/src/transport/`, `app/modules/`, `useAirMouse.ts` or native iOS files.
- Don't deploy to the iPhone. Run `cd app && npm test && npx tsc --noEmit && npx expo lint` only; the orchestrator deploys.
- **Mac:** `swift test`, then `./build.sh`. Render previews of the explainer pages and view them. Then quit the app, replace /Applications/AirMouse.app and `open` it.
- tmux rule: never touch `cjm-landing-tmux`. No `tmux kill-server` and no `kill-session -a`.

Print a 3-line summary.
