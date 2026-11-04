# Task 08: Landing page to install AirMouse for Mac

You are kasuki (Codex). Repo root: `airmouse/` (cwd). Tasks 05–07 produced the app icon, the illustrations, `assets-gen/mac3d/` (3D art) and the restyled apps. Reuse them. Read `docs/spec-v3.md` sections 0 and 1.

## Part 0 (do first): fix the Mac redesign from task 06 (owner screenshot review)
- **Sidebar** is still the old light-grey list and clashes with the purple content. Make it dark and translucent over the aurora (vibrancy `.sidebar` with a dark tint), with white text and a glowing selected pill. The title bar area must not be light grey: use `.windowStyle(.hiddenTitleBar)` / full-size content view so the gradient runs under it.
- **Cards** are washed-out lavender with dark text, so contrast is low. Use dark glass (black 25–35% plus blur, a 1 px white 12% border) with white text and secondary text at white 65%, so they look like CleanMyMac's dark purple cards.
- **The big round gradient "Calibrate" button** is missing from Home, or sits off-screen at the default window size. It must be visible without scrolling at 900×640.
- **Date** shows "4 Nov 2569 BE". Always format with `Locale(identifier: "en_US_POSIX")` and the Gregorian calendar, e.g. "Nov 4, 2026".
- The 5th card leaves an empty slot. Balance the grid: make Permissions full width or reflow.
- Rebuild, reinstall and re-render the previews. View them yourself before moving on.

## Goal
Rebuild `web/` as a polished one-page landing site whose main job is installing the **native Mac app**. Keep it static: plain HTML, CSS and a little JS, no framework, so it can be hosted on GitHub Pages.

The style matches the apps: CleanMyMac / Apple product page feel, deep purple aurora gradient, glass cards, glossy 3D art, SF Pro via the system font stack, big type and smooth scroll-in animations (respect `prefers-reduced-motion`). Copy is English. Make it responsive for desktop and mobile.

## Sections
1. **Hero**
   - App icon, "AirMouse", tagline "Point at your Mac with your iPhone."
   - Primary button "Download for Mac", pointing to `downloads/AirMouse.dmg`, with the version and "macOS 14+, Apple silicon & Intel" underneath.
   - Secondary link "How it works".
   - Hero art: an iPhone pointing at a Mac with a beam (generate it, or compose from the existing art).
2. **How it works:** 3 illustrated steps: Install on Mac, Open on iPhone and pair, Calibrate and point.
3. **Features:** grid of glass cards with icons:
   - Wi-Fi and Bluetooth
   - 5-point calibration
   - Keyboard typing
   - Click practice
   - Smooth 120 Hz pointer
   - Private: local network only
4. **Install guide (important):**
   - Step by step: open the DMG, drag to Applications, first launch (the app isn't notarized yet, so explain right-click → Open, or System Settings → Privacy & Security → "Open Anyway"), then grant Accessibility, with an illustration per step.
   - FAQ: Accessibility, Local Network, Bluetooth, and why the Mac must be on the same Wi-Fi.
5. **iPhone app:** "Coming to the App Store", plus a short note that it is currently installed by the developer. No fake store badge.
6. **Footer:** GitHub link https://github.com/NATX0XD/airmouse, "Made by Nattakit · KMUTNB", MIT-style note optional.

Icons: use inline SVG icon components (Lucide/SF-like strokes) or generated images. Remove old Android APK and Windows content from the page, but leave the old files on disk alone.

## DMG
- Add `tools/make-dmg.sh`. It builds with `desktop/mac/build.sh`, then makes `web/downloads/AirMouse.dmg` with `hdiutil`: a drag-to-Applications layout with an /Applications symlink. If `create-dmg` is installed, use it for a nice background.
- Write `web/downloads/manifest.json` with the version, size, sha256 and date.
- `web/downloads/` is gitignored. Keep it that way. Document that the DMG is uploaded as a GitHub Release asset, and have the page's download button point to `https://github.com/NATX0XD/airmouse/releases/latest/download/AirMouse.dmg`, falling back to the local `downloads/AirMouse.dmg`.

## Verify
- Run `tools/make-dmg.sh` and check that the DMG mounts and contains AirMouse.app: use `hdiutil attach -nobrowse`, then detach.
- Serve `web/` with `python3 -m http.server` on a free port.
- Screenshot it with headless Chrome at desktop width (1440) and mobile width (390), for example `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --screenshot`. View the screenshots and iterate until they look polished. Save the final ones to `web/screenshots/`.
- Kill the server and every headless browser when done.
- No git commits; the orchestrator commits. Don't touch `mobile/` or `flight/`.

## tmux rule
`cjm-landing-tmux` belongs to the owner: never attach, send-keys, kill or read its pane. Never run `tmux kill-server` or `tmux kill-session -a`. Only create or touch `vx-` sessions, and close them by exact name.

## Report
Print a short summary: files, DMG path and size, and screenshot paths.
