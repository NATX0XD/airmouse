# AirMouse generated visual assets

Visual direction follows `docs/spec-v3.md`: Apple-inspired, minimal soft depth, Aurora `#0A84FF → #5E5CE6 → #BF5AF2`, and cyan calibration glow `#64D2FF`. Raster art was generated with the built-in image generation tool where organic illustration helped; crisp symbols, diagrams, and particles were authored as SVG and rasterized with `rsvg-convert`.

| File | Size | Transparent | Intended screen / use | Notes |
|---|---:|:---:|---|---|
| `icon/app-icon-1024.png` | 1024² | yes | iOS app icon | Vector-authored Aurora squircle + cursor rays |
| `icon/app-icon.svg` | 1024² | yes | iOS/macOS source | Same icon, editable source; transparent outside squircle |
| `icon/mac-icon-1024.png` | 1024² | yes | macOS app icon | Rounded macOS grid treatment |
| `icon/mac-icon.svg` | 1024² | yes | macOS source | Same icon, editable source; transparent outside rounded tile |
| `illustrations/hero-pointing.png` | 1600×1200 | yes | Connect hero | Generated raster; generic phone, laptop, hand; no text/logos |
| `illustrations/calib-place.png` | 1200² | yes | Calibration placement | Generated raster; dark display, cyan outline, particles |
| `illustrations/calib-point-left.png` | 1200×900 | yes | Legacy/pointing guidance | SVG-authored, rasterized |
| `illustrations/calib-point-right.png` | 1200×900 | yes | Legacy/pointing guidance | SVG-authored, rasterized |
| `illustrations/calib-done.png` | 800² | yes | Calibration success | Aurora glow + green check |
| `illustrations/connect-wifi.png` | 512² | yes | Wi-Fi connection option | Vector spot illustration |
| `illustrations/connect-bluetooth.png` | 512² | yes | Bluetooth connection option | Vector spot illustration |
| `illustrations/connect-qr.png` | 512² | yes | QR connection option | Vector spot illustration |
| `illustrations/connect-ip.png` | 512² | yes | IP address option | Vector spot illustration |
| `infographics/gyro-axes.svg` | 1200² | yes | Sensors screen | X pitch red, Y roll green, Z yaw blue |
| `infographics/gyro-axes.png` | 1200² | yes | Sensors screen | Raster export of SVG |
| `infographics/how-it-works.svg` | 1600×900 | no | Course presentation / explainer | 3-step gyroscope → filter → Mac cursor |
| `infographics/how-it-works.png` | 1600×900 | no | Course presentation / explainer | Raster export of SVG |
| `mac/overlay-particles.svg` | 2560×1440 | no | Mac calibration overlay source | Dark base + sparse cyan/blue particles |
| `mac/overlay-particles.png` | 2560×1440 | no | Mac calibration overlay | Tile-friendly sparse base texture |

All smaller raster illustrations are already 512px or larger and can be downsampled by iOS/macOS asset catalogs for 2×/3× use; no extra lossy variants were needed. The two generated images were inspected for alpha, stray text, visible logos, broken outlines, and obvious anatomy/device artifacts. `calib-place.png` intentionally shows the rear camera module because the v3 flow places the display-facing screen against the display; the display-facing side remains the screen-facing guidance object in the surrounding UI.

Legacy files `icon/icon-ios.*`, `icon/icon-mac.*`, and `icon/gen.py` pre-existed in `assets-gen/` and were left untouched for the lead agent to decide whether to remove or migrate.
