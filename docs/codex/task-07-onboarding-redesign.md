# Task 07: Welcome and permission stepper redesign (Mac and iPhone)

You are kasuki (Codex). Repo root: `airmouse/` (cwd). Task 06 (Mac redesign, CleanMyMac style) ran just before this one. Reuse its theme, the 3D art in `assets-gen/mac3d/` and the illustrations from task 05. Read `docs/spec-v3.md` sections 1, 2 and 2a. The flow order, the permission logic and the checks stay exactly as they are: this is a visual and UX polish only.

## Goal
The first-run experience on both apps should look premium and inviting, in the CleanMyMac style:
- deep purple/indigo aurora background
- big glossy 3D illustration per step
- large bold title, one short line of body text
- glass cards
- one big gradient primary button
- step dots with smooth transitions

## Mac (`desktop/mac/Sources/AirMouse/OnboardingViews.swift`, `SetupView.swift`)
- **Welcome:** hero 3D art plus a short "how it works" row with 3 illustrated steps: iPhone → calibrate → point.
- **Get the iPhone app:** shows a phone mock-up.
- **Permission stepper:** one glass card per permission (Accessibility, Bluetooth, Local Network if present).
  - Each card has its 3D icon, a one-line reason, and a status pill: Needed (amber), Checking… (animated), Granted (green check with a pop animation).
  - The "Open System Settings" button keeps its current behaviour.
  - Cards auto-advance when the status changes to granted (the existing polling).
- **Done:** a celebratory step that hands off to the guided tour.
- Keep all actions and polling as they are. It must look good at the minimum window size.

## iPhone (`app/src/screens/WelcomeFlow.tsx`, `SetupFlow.tsx`, `src/ui`)
- The same structure and style: full-screen aurora gradient (`expo-linear-gradient`), a large illustration per page, glass cards (`expo-blur` / `expo-glass-effect`), and a big gradient button.
- Animated page transitions and step dots.
- **Permission stepper:** Motion, Local Network, Bluetooth and Camera (QR), with the same card and pill design and the existing request and check logic.
- Illustrations:
  - Generate matching 3D PNGs into `app/assets/illustrations/` (transparent, 512–1024 px, same style as task 06) and wire them up with `require`.
  - If generation is unavailable, use layered vector art with `react-native-svg`. No placeholders.
- Use English copy and SF Pro, and keep accessibility labels.

## Verify
**Mac:**
- `swift test` passes.
- `build.sh` succeeds.
- Render the onboarding previews with `--render-previews`, view the PNGs and iterate until they look polished.
- Copy them to `desktop/mac/previews/`.
- Reinstall into /Applications: quit first, replace, then `open`. Keep the signing identity build.sh uses.

**iPhone:**
- `cd app && npm test && npx tsc --noEmit && npx expo lint`: all clean.
- If the phone "Ghost" is available (`xcrun devicectl list devices`), install with `tools/deploy-ios.sh`. Otherwise, build only with `tools/deploy-ios.sh --build`.
- Never run `expo prebuild --clean`.

**Both:**
- Don't post mouse or keyboard events.
- Don't touch `mobile/` or `flight/`.
- No git commits. The orchestrator commits.

## tmux rule
`cjm-landing-tmux` belongs to the owner: never attach, send-keys, kill or read its pane. Never run `tmux kill-server` or `tmux kill-session -a`. Only create or touch `vx-` sessions, and close them by exact name.

## Report
Print a short summary: files changed, the illustration source (generated or vector), preview paths, and whether the iPhone build was installed.
