# Task 10: Mac visual quality pass, Apple-native (owner: the cards and menu still don't look good)

You are kasuki (Codex). cwd is `airmouse/`. Touch only `desktop/mac`. No git commits. Keep behaviour.

**The owner's binding direction is the Apple iOS/macOS design language** (spec-v3 section 1). It should look like a first-party Apple app on macOS Sequoia, such as System Settings, Find My or the Apple TV app, with the 3D illustrations as a tasteful accent. It should not look like a custom web-style theme.

- **Appearance.** Remove the forced dark mode: `NSApp.appearance` and `.preferredColorScheme(.dark)` in AirMouseApp.swift. Support light and dark properly with system semantic colours (`.background`, `.secondary`, materials). Each mode must look polished. Check the previews in both.
- **Window.** Use a standard NavigationSplitView with the native sidebar (`.listStyle(.sidebar)`, translucent vibrancy, unified toolbar). No custom purple full-window gradient. The aurora gradient appears only as an accent: the hero header and the primary button.
- **Sidebar.** Like System Settings: SF Symbol icons in small coloured rounded squares (system colours), standard row height, native selection highlight in the accent colour, a section header, and the connection status row at the bottom. Remove any custom pill or glow.
- **Cards.** Native grouped style: `.regularMaterial` or `.background.secondary` fill, radius 12–16, a subtle shadow in light mode. Use the SF Pro hierarchy: a headline, a large title for values, and a secondary caption.
  - Put the 3D illustrations inside the cards at a moderate size (about 72–88 pt) on the leading or trailing side, never clipped.
  - Buttons are native: `.borderedProminent` for the primary action, `.bordered` for the others, control size large.
- **Home.** Must fit at 900×640 with no scrolling:
  - a hero header with the AirMouse title and status, plus the primary "Calibrate" button (`.borderedProminent`, with the aurora gradient tint allowed);
  - then a clean grid: Connection, Calibration, Practice, Pair, Permissions;
  - remove the floating round button.
- Bring Pair, Permissions, Calibration, About, the onboarding/welcome and the permission stepper to the same Apple-native language. The stepper should look like Apple setup assistants: a big centred illustration, a title, one line of body text, a list of permission rows with status, and Continue at the bottom.

Verify:
- `swift test`
- `./build.sh`
- Render previews at 900×640 in light AND dark mode and view them. Do at least 2 self-review rounds.
- Then quit the app, replace /Applications/AirMouse.app and run `open`.

tmux rule: never touch `cjm-landing-tmux`. No `tmux kill-server` and no `kill-session -a`.

Print a 3-line summary.
