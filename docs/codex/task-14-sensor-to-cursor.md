# Task 14: "From Sensor to Cursor" visual stepper (Settings only, Mac and iPhone)

You are kasuki (Codex). cwd is `airmouse/`. No git commits. Same Apple-native design and glossy 3D art style as tasks 12/13.

## Goal
Add a new stepper that explains, **visually and in plain everyday English**, how the gyroscope data becomes cursor movement.
- **Do NOT add it to onboarding or Welcome.** It opens only from **iPhone: Settings → Help → "From Sensor to Cursor"** and **Mac: About → "From Sensor to Cursor"**.
- Each page has one big infographic or illustration, a short title and 1–2 short sentences. Add small animated diagrams where they help, built in code (arrows, numbers ticking, a moving dot). Respect Reduce Motion.

## Pages (source facts; keep them accurate, but simplify the wording)
1. **The gyroscope measures turning speed.** It doesn't know where you point; it only knows how fast you are turning. It checks 100 times a second (every 10 ms). Visual: phone with three rotation arrows.
2. **Three directions.** Turning left/right moves the cursor sideways. Tilting the top up/down moves it up/down. Twisting your wrist is ignored. Visual: phone with yaw, pitch and roll arrows; roll is greyed out.
3. **Removing the drift.** Even lying still, the sensor reads a tiny bit wrong (this is called bias). During calibration, AirMouse measures it while the phone rests on the screen for 2 seconds, then subtracts it, so the cursor doesn't creep by itself. Visual: a drifting dot that becomes still.
4. **Calming shaky hands.** A smart filter (the One Euro filter) smooths slow, shaky movements but lets quick moves through instantly. Tiny wobbles are gently squashed to almost zero. Visual: a jittery line next to a smooth line.
5. **Speed × time = distance.** Turning speed × time × your calibration setting = how many dots the cursor moves.
   - Worked example: turning at about 29° per second for 10 ms moves the cursor about 7 dots, so about 700 dots in one second.
   - Flicking fast adds a little extra (acceleration).
   - Visual: an animated equation with numbers.
6. **Calibration sets the scale.** Pointing at 5 dots teaches AirMouse how many dots one degree of turning should be, separately for sideways and up/down. Visual: a screen with 5 dots and angle lines from the phone.
7. **A tiny message to your Mac.** The phone sends a short note, e.g. `move 7.9 right, 0.4 up`.
   - Wi-Fi: about 100 times a second.
   - Bluetooth: about 11 times a second; notes that can't be sent in time are combined.
   - Only while you hold the pad (Hold to Point), or always (Always On).
   - Visual: the phone sending little message bubbles to the Mac.
8. **The Mac moves the real cursor smoothly.** The Mac app gathers the notes and moves the cursor a little every screen refresh (up to 120 times a second). If a note arrives late, the cursor glides instead of stopping. Visual: bursty dots in, an even stream out.
9. **Summary.** The whole chain on one infographic: Gyroscope → remove drift → smooth → × time × calibration → message → Mac smooths → cursor. Footnote: "The accelerometer and proximity sensor are only used during calibration; the touchscreen clicks and turns pointing on and off."

## Art
Generate the illustrations and infographics with your image tool into `assets-gen/sensor-to-cursor/`. Keep text out of the images; overlay the text in UI code so it stays crisp. Copy them into the Mac bundle (build.sh) and into `app/assets/illustrations/sensor-to-cursor/`. Reuse the existing explainer stepper component patterns.

## Constraints
- Don't touch `app/src/transport/`, `app/modules/` or `useAirMouse.ts`.
- **iPhone:** `npm test`, `npx tsc --noEmit`, `npx expo lint`. Don't deploy; the orchestrator deploys.
- **Mac:** `swift test`, then `./build.sh`. Render previews of the pages and view them, in light and dark mode. Make sure text is readable in both, which is a known past issue. Then quit the app, replace /Applications/AirMouse.app and `open` it. Delete any backup copies in /Applications.
- tmux rule: never touch `cjm-landing-tmux`. No `tmux kill-server` and no `kill-session -a`.

Print a 3-line summary.
