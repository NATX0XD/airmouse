# AirMouse wire protocol v2 (shared by app, desktop receiver, dongle)

Owner of this file: yasuri. Both Codex sessions implement exactly this. Do not change it; if something is impossible, write it in your report.

## Phone -> target

JSON over WebSocket (WiFi mode), one object per message:

| Msg | Meaning |
|---|---|
| `{t:'hello', v:2, app:'airmouse'}` | first message after connect |
| `{t:'move', dx, dy}` | relative move, integers, screen pixels (+x right, +y down) |
| `{t:'button', b:'left'\|'right', down:bool}` | press / release |
| `{t:'scroll', dy}` | integer notches, positive = scroll down |
| `{t:'key', k:'left'\|'right'}` | arrow key tap (slide control) |
| `{t:'center'}` | **new**: put the cursor in the middle of the main screen |

## Target -> phone (WiFi only)

| Msg | When |
|---|---|
| `{t:'screen', w, h, scale}` | reply to `hello`, and again if the main screen size changes. `w`,`h` = main display size in the same units `move` uses (logical points on macOS, pixels on Windows with DPI awareness on). `scale` = backing scale factor (1 if unknown). |

Unknown message types must be ignored, not crash (both directions). Old receivers that never send `screen`: the app falls back to the screen size typed in Settings (default 1920x1080).

## 5-byte report (BLE dongle, Android HID)

`[buttons, dx, dy, wheel, key]` unchanged from task 01 (`app/src/transport/report.ts`).
`center` cannot be expressed as absolute in a relative mouse, so the app's `ReportEncoder` emits it as: move by (-W*2, -H*2) split into 127-steps (slam into the top-left corner), then (+W/2, +H/2), using the known screen size. Document in UI that this is approximate on HID/dongle because OS pointer acceleration changes large moves.
