# Codex task 05: generate the visual assets (icons, illustrations, infographics)

You are **kasuki** (Codex). Lead: **yasuri** (Claude). Owner: Thai student, KMUTNB mobile course mini project 1 (sensor app). Use your **image generation** tool for raster art; produce vector (SVG) yourself where crisp geometry matters.

Working directory: `/Users/nattakit/Desktop/Project/TCT-KMUTNB/MobileApp/mini-1-sensor-Apps/airmouse`

Read first: `docs/spec-v3.md` (section 1 design system, section 4 calibration flow). The product: **AirMouse** turns an iPhone into an air mouse for a Mac (turn the phone, the cursor follows). Two apps: iPhone + Mac. All text inside images must be **English** (prefer no text in images at all; the apps render text).

## Rules
- tmux: never touch `cjm-landing-tmux`, never `tmux kill-server` / `kill-session -a`; only `vx-` sessions.
- Write **only** into `assets-gen/` (create it). Other agents own `app/` and `desktop/mac/`; yasuri integrates your files. No git commit.
- Do not open GUI apps or move the mouse. Kill processes you start.
- Style for everything: Apple design language (iOS 27 / macOS 27), minimal, colourful, clean, soft depth, lots of breathing room. Brand gradient "Aurora" `#0A84FF -> #5E5CE6 -> #BF5AF2`; calibration glow cyan `#64D2FF`. Devices drawn as generic modern iPhone / MacBook-like silhouettes **without Apple logos or trademarked UI**. No photographic people; a stylised hand is OK.
- Every illustration: transparent background PNG (or note if the generator cannot do transparency: then deliver on pure white AND pure black variants, and also try background removal), plus light/dark suitability noted.

## Assets
| # | File (in `assets-gen/`) | Spec |
|---|---|---|
| 1 | `icon/app-icon-1024.png` + `icon/app-icon.svg` | App icon for iOS and macOS: Aurora gradient squircle, white glyph = a cursor arrow with 2-3 motion rays (think SF Symbol `cursorarrow.rays`), subtle inner glow. No text. Also `icon/mac-icon-1024.png` with the macOS icon grid (rounded rect with margin + soft shadow per macOS 27 template). |
| 2 | `illustrations/hero-pointing.png` (1600x1200) | Hand holding an iPhone like a TV remote, pointing at a laptop; a glowing cursor trail on the laptop screen. Used on the Connect screen hero. |
| 3 | `illustrations/calib-place.png` (1200x1200) | Calibration step 1: an iPhone held flat against a dark display inside a glowing cyan phone-shaped outline, particles around (Apple TV colour-balance vibe). |
| 4 | `illustrations/calib-point-left.png`, `calib-point-right.png` (1200x900) | Phone held like a remote, pointing at a glowing dot on the left / right edge of a display. |
| 5 | `illustrations/calib-done.png` (800x800) | Success: soft Aurora glow with a check mark badge. |
| 6 | `illustrations/connect-wifi.png`, `connect-bluetooth.png`, `connect-qr.png`, `connect-ip.png` (512x512 each) | Small spot illustrations for the four connection options (same style family, same lighting, transparent). |
| 7 | `infographics/gyro-axes.svg` + `.png` (1200x1200) | iPhone in perspective with the three gyroscope axes as coloured arrows: X (pitch) red `#FF453A`, Y (roll) green `#30D158`, Z (yaw) blue `#0A84FF`, curved rotation arrows, labels "X  pitch", "Y  roll", "Z  yaw" (English, SF-like font or none and leave label anchors). Used on the Sensors screen. |
| 8 | `infographics/how-it-works.svg` + `.png` (1600x900) | 3-step flow: gyroscope -> filter (One Euro, dead zone) -> cursor on Mac via Wi-Fi/Bluetooth. Simple icons, arrows, minimal labels in English. For the course presentation too. |
| 9 | `mac/overlay-particles.png` (2560x1440, tileable if possible) | Dark background texture with sparse blue/cyan particles for the Mac calibration overlay (the app may also animate particles in code; this is the base layer). |

For each raster: also export `@2x`/`@3x`-friendly sizes if smaller variants are needed for iOS (`*-512.png` etc.), keep originals.

## Deliver
- `assets-gen/README.md`: table of every file, size, transparent yes/no, intended screen, and any generator limitation.
- Check every image yourself (open/inspect it) for artifacts: extra fingers, warped devices, stray text, logos. Regenerate bad ones (up to 3 tries each).
- Last line of output: `TASK-05 DONE` or `TASK-05 PARTIAL: <what is missing + why>`.
