# Task 06: Mac app visual redesign (CleanMyMac style)

You are kasuki (Codex). Repo root: `airmouse/` (cwd). Read `docs/spec-v3.md` sections 1 and 5 first. The binding behaviour stays as it is: this is a visual redesign only. Don't change the protocol, the logic or the AirMouseCore code.

## Goal
The owner wants the native Mac app (`desktop/mac`, SwiftUI, SwiftPM) to look premium and inviting, in the style of **CleanMyMac (MacPaw, 2024+ redesign)**:
- The whole window has a deep purple/indigo aurora gradient background, the same in light and dark mode.
- The sidebar is translucent and icon-forward (wide-icon or icon-only) with a glowing selected state.
- Large rounded glass cards (radius about 20, white about 8% fill, a 1 px white about 12% border). Each card has a big glossy **3D illustration** that bleeds off the card's top-right corner, a large bold value or title, a small caption and a small pill button ("Review" style).
- There is a big round gradient primary action button, like CleanMyMac's "Run" button, used for "Calibrate" on Home.
- Use SF Pro Display or Rounded for big numbers, generous spacing, and soft colourful shadows/glows.

## Steps
1. **3D illustrations.** Generate them with your image tool and save them to `assets-gen/mac3d/` as PNG with transparent background, 512 px, all in one consistent glossy 3D style (soft plastic/glass, rim light, purple/blue/pink/cyan palette matching the Aurora tokens #0A84FF #5E5CE6 #BF5AF2 #64D2FF):
   - `iphone-remote.png`: phone with a pointer beam (Connection / Pair)
   - `target.png`: crosshair or bullseye (Calibrate)
   - `cursor-click.png`: cursor with a click ripple (Practice)
   - `shield-check.png`: shield (Permissions)
   - `waves.png`: Wi-Fi/Bluetooth waves (connection status)
   - `gauge.png`: speed gauge (Calibration value / speed)
   - `info.png`: info bubble (About)

   If image generation is unavailable, draw them as layered SwiftUI vector art (gradients, highlights, shadows) instead. Don't leave placeholders.
2. **Wire them into the build.** Copy them into the app bundle in `desktop/mac/build.sh`, the same way the existing illustrations are copied, and load them with a helper that falls back to SF Symbols when a file is missing.
3. **Redesign** `Theme.swift`, `MainView.swift`, `Sections.swift`, `OnboardingViews.swift` and `SetupView.swift`:
   - **Home** becomes a grid of cards:
     - Connection: status, with Wi-Fi and BLE as sub-rows
     - Calibration: value, date, a "Recalibrate" pill
     - Practice Clicking
     - Pair iPhone
     - Permissions: all-green or "1 needs attention"

     Put the big round "Calibrate" button at the bottom centre. The title reads "AirMouse", with "Your iPhone is ready to point." / "Waiting for your iPhone…".
   - The **other sections** (Pair, Permissions, Calibration, About) get the same background, glass cards and illustrations.
   - **Fix the text truncation** visible today: "Gyroscope" and "Smoothing" wrap mid-word in the How It Works card, and "Practice Clicking" wraps in its button. Use `lineLimit(1)` and `minimumScaleFactor`, or a better layout.
   - It must work at the minimum window size (about 740×600) and when the window is larger.
4. **Onboarding overlays and the calibration overlay** keep their current behaviour. Restyle the onboarding windows only, so they match.

## Verify
- `cd desktop/mac && swift test`: all pass.
- `./build.sh` succeeds.
- `./dist/AirMouse.app/Contents/MacOS/AirMouse --render-previews /tmp/am-prev`: view the PNGs and iterate until they look polished.
- Copy the final previews to `desktop/mac/previews/`.
- Reinstall: `osascript -e 'quit app "AirMouse"'`, replace `/Applications/AirMouse.app` with `dist/AirMouse.app`, then `open` it. Keep the signing identity that build.sh uses, so the Accessibility grant persists.
- Don't post mouse or keyboard events. Don't touch `app/`, `mobile/` or `flight/`. No git commits.

## tmux rule
`cjm-landing-tmux` belongs to the owner: never attach, send-keys, kill or read its pane. Never run `tmux kill-server` or `tmux kill-session -a`. Only create or touch sessions prefixed `vx-`, and close them by exact name.

## Report
At the end, print a short summary: files changed, the illustration source (generated or vector), and the preview paths.
