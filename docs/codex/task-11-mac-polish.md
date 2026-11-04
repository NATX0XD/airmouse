# Task 11: Mac polish round (owner screenshot review)

You are kasuki (Codex). cwd is `airmouse/`. Keep the Apple-native macOS direction from task 10: light/dark, native sidebar, SF Pro, materials. Touch `desktop/mac`, `assets-gen/` and `app/assets/icon.png` only. No git commits.

## 1. New art (use your image generation tool)
- **App icon.** A new AirMouse app icon in the Apple macOS Sequoia icon style: a squircle with a glossy 3D iPhone sending a light beam to a cursor, aurora blue→purple. Make two variants:
  - Mac: `desktop/mac/Resources/AppIcon-1024.png`, with Apple's icon grid padding and shadow.
  - iOS: `app/assets/icon.png`, full-bleed, opaque, no alpha. Flatten it, e.g. with `sips` jpeg→png.

  Keep the sources in `assets-gen/icon/`.
- **"How It Works" infographic.** Replace `assets-gen/infographics/how-it-works.png`; today's version is a crude flat vector. It should be a polished 3-step Apple-keynote-style illustration in the same glossy 3D style as `assets-gen/mac3d/`:
  1. iPhone gyroscope
  2. smoothing
  3. cursor on the Mac

  Use a light background that works in both modes, or build the step row in SwiftUI from three separate 3D images with short labels. That is preferred, so the text stays crisp.

## 2. Onboarding
- **"Get AirMouse on Your iPhone"** must not hard-code "Nattakit MacBook". Use this Mac's real name (`Host.current().localizedName`, or the same name the Bonjour service advertises). Make the layout look like an Apple setup page: a big illustration at the top centre, a title, numbered steps, and a real QR code for pairing if one is available (the pairing QR the app already makes), otherwise a tidy note.
- **Permission stepper** is cluttered today. "Almost ready" and "AirMouse Is Ready 4/4" duplicate each other, the cards expand with an extra Continue button, and it scrolls. Redesign it:
  - one header (illustration, title, subtitle);
  - a compact list of permission rows (icon, name, one line of text, then status: a green check, or an "Allow…" button);
  - no accordion and no per-row Continue;
  - a single primary button at the bottom;
  - it must fit at 900×640 without scrolling.

## 3. Home and sidebar
- **Sidebar:** make it look like System Settings or Music on Sequoia. Proper row height and spacing, an app header with the icon and name at the top, and the connection status at the bottom as a small card (device name and coloured dot).
- **Fix overlaps:** the Connection card illustration covers the "Listening" text. Keep the art in its own column and never let it overlap the text.
- **Grid:** fill the empty slot. Either make Permissions span both columns, or use a 3-column top row.
- **Connected state must look clearly different.** When an iPhone is connected, the Home header becomes a hero card:
  - "Connected to <iPhone name>" with an animated pulse ring, the transport (Wi-Fi/Bluetooth), live moves per second, and a latency/jitter indicator from the existing Diagnostics;
  - quick actions: Calibrate, Practice, Center Cursor.

  When nothing is connected, show a "Waiting for your iPhone" hero with a gentle animation and a Pair button.
- **Animations** (respect Reduce Motion):
  - cards lift slightly on hover (scale 1.01, shadow up, 0.2 s spring) and buttons highlight on hover;
  - the sidebar selection animates;
  - section transitions cross-fade;
  - illustrations float slowly;
  - status dots pulse.

## Verify
- `swift test`
- `./build.sh`
- Render previews (Home connected and disconnected, onboarding pages, permissions) at 900×640 in light and dark mode. View them yourself, with 2 review rounds.
- Then quit the app, replace /Applications/AirMouse.app and run `open`.

tmux rule: never touch `cjm-landing-tmux`. No `tmux kill-server` and no `kill-session -a`.

Print a 3-line summary.
