# Task 08: Mac redesign fixes

You are kasuki (Codex). Repo root: `airmouse/` (cwd). Touch only `desktop/mac`. Don't touch `web/`, because another agent owns it. No git commits.

## Fix the Mac redesign from task 06 (owner screenshot review)
- **Sidebar** is still the old light-grey list and clashes with the purple content. Make it dark and translucent over the aurora (vibrancy `.sidebar` with a dark tint), with white text and a glowing selected pill. The title bar area must not be light grey: use `.windowStyle(.hiddenTitleBar)` / full-size content view so the gradient runs under it.
- **Cards** are washed-out lavender with dark text, so contrast is low. Use dark glass (black 25–35% plus blur, a 1 px white 12% border) with white text and secondary text at white 65%, so they look like CleanMyMac's dark purple cards.
- **The big round gradient "Calibrate" button** is missing from Home, or sits off-screen at the default window size. It must be visible without scrolling at 900×640.
- **Date** shows "4 Nov 2569 BE". Always format with `Locale(identifier: "en_US_POSIX")` and the Gregorian calendar, e.g. "Nov 4, 2026".
- The 5th card leaves an empty slot. Balance the grid: make Permissions full width or reflow.
- Rebuild, reinstall and re-render the previews. View them yourself before moving on.

## tmux rule
`cjm-landing-tmux` belongs to the owner: never attach, send-keys, kill or read its pane. Never run `tmux kill-server` or `tmux kill-session -a`. Only create or touch `vx-` sessions, and close them by exact name.

## Report
Print a short summary: files changed and preview paths.
