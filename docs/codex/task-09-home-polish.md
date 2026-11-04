# Task 09: Mac Home polish (owner screenshot at the default 900x640 window)

You are kasuki (Codex). cwd is `airmouse/`. Touch only `desktop/mac`. No git commits. The app is now forced to dark appearance (AirMouseApp.swift). Keep that.

Fix in `Sections.swift` and `Theme.swift`:
1. **The round "Calibrate" button is cut off at the bottom** at 900x640. Everything on Home, including the button and its label, must fit without scrolling at 900x640. Tighten the vertical spacing, make the cards shorter, or put the button in the header row on the right.
2. **The 3D art is clipped by the card's top edge.** The art should overflow the card's top-right corner (not clipped) like CleanMyMac, or sit fully inside. No hard cut lines.
3. **The cards in each row must be equal height and aligned.** The Connection and Calibration tops are misaligned today. Use a Grid with equal row heights.
4. Add a subtle purple tint to the card glass so it isn't grey-black: about 8% #5E5CE6 over the dark fill.

Verify:
- `swift test`
- `./build.sh`
- Render previews at 900x640 and view them.
- Then quit the app (`osascript -e 'quit app "AirMouse"'`), replace /Applications/AirMouse.app, then `open` it.

tmux rule: never touch `cjm-landing-tmux`. No `tmux kill-server` and no `kill-session -a`.

Print a 3-line summary.
