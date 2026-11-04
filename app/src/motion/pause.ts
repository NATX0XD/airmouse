// Who is holding the pointer still. Pure, so it runs under `node --test`.
//
// Pointing is paused while at least one owner holds a pause (today only the
// calibration flow). Owners are idempotent: pausing twice and resuming once
// resumes, so a missed or doubled call can never leave motion stuck off.
// `clear()` is the escape hatch for app background / disconnect.

export type PauseOwner = 'calibration';

export class PauseLatch {
  private owners = new Set<PauseOwner>();

  // Returns true when the overall paused state changed.
  set(owner: PauseOwner, on: boolean): boolean {
    const before = this.paused;
    if (on) this.owners.add(owner);
    else this.owners.delete(owner);
    return before !== this.paused;
  }

  clear(): boolean {
    const before = this.paused;
    this.owners.clear();
    return before;
  }

  get paused(): boolean {
    return this.owners.size > 0;
  }

  list(): PauseOwner[] {
    return [...this.owners];
  }
}

// The calibration pause is derived from what is on screen, not from the
// flow's own effects: open (and not a screenshot preview) and the app in the
// foreground = paused; anything else = pointing.
export function calibrationPaused(p: { calibOpen: boolean; preview: boolean; appActive: boolean }): boolean {
  return p.calibOpen && !p.preview && p.appActive;
}

// Calibration exit rules (docs/spec-v3.md 4a.2): the flow closes itself when
// the app goes to the background or a connection that existed when it
// started goes away. Returns true when the flow should close.
export function calibrationShouldClose(p: { calibOpen: boolean; appState: string; startedConnected: boolean; connected: boolean }): boolean {
  if (!p.calibOpen) return false;
  if (p.appState === 'background') return true;
  return p.startedConnected && !p.connected;
}
