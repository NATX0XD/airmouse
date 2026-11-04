// First-run onboarding and guided tour (docs/spec-v3.md section 2). Pure.
// Order: Welcome pages -> Get AirMouse for Mac -> Permissions -> Connect ->
// guided tour on Remote after the first successful connection.

export const FLAG_KEYS = {
  welcome: 'airmouse.welcome.v1',
  setup: 'airmouse.setup.v1',
  tour: 'airmouse.tour.v1',
} as const;

export type Flags = { welcome: boolean; setup: boolean; tour: boolean };

export type WelcomePage = 'welcome' | 'how' | 'getMac';
export const WELCOME_PAGES: WelcomePage[] = ['welcome', 'how', 'getMac'];

export type Pager = { index: number; done: boolean };
export const pagerNext = (p: Pager, count: number): Pager => (p.index + 1 >= count ? { index: count - 1, done: true } : { index: p.index + 1, done: false });
export const pagerBack = (p: Pager): Pager => ({ index: Math.max(0, p.index - 1), done: false });

// What to show at launch, given the stored flags and whether a Mac is saved.
export type LaunchStep = 'welcome' | 'setup' | 'connect' | 'app';
export function launchStep(flags: Flags, hasSavedMac: boolean): LaunchStep {
  if (!flags.welcome) return 'welcome';
  if (!flags.setup) return 'setup';
  return hasSavedMac ? 'app' : 'connect';
}

// After each onboarding stage, where to go next.
export function afterStage(stage: 'welcome' | 'setup', flags: Flags, hasSavedMac: boolean): LaunchStep {
  const f = { ...flags, [stage]: true };
  return launchStep(f, hasSavedMac);
}

export type TourTarget = 'pill' | 'pad' | 'scroll' | 'clicks' | 'center' | 'calibrate' | 'settingsTab';
export type TourStep = { target: TourTarget; title: string; body: string };

export const TOUR: TourStep[] = [
  { target: 'pill', title: 'Your Mac', body: 'Shows what you’re connected to. Tap it to switch Macs.' },
  { target: 'pad', title: 'Hold to Point', body: 'Keep a finger here and turn your iPhone. Tap to click.' },
  { target: 'scroll', title: 'Scroll', body: 'Slide up or down here to scroll.' },
  { target: 'clicks', title: 'Left and Right Click', body: 'Press and hold to drag, or right-click for menus.' },
  { target: 'center', title: 'Center', body: 'Lost the pointer? This puts it in the middle of the screen.' },
  { target: 'calibrate', title: 'Calibrate', body: 'Match the speed to your screen and remove gyro drift.' },
  { target: 'settingsTab', title: 'Settings', body: 'Tune speed and smoothing, or replay this tour.' },
];

export type Tour = { index: number; active: boolean };
export const TOUR_IDLE: Tour = { index: 0, active: false };
export const tourStart = (): Tour => ({ index: 0, active: true });
export const tourNext = (t: Tour): Tour => (t.index + 1 >= TOUR.length ? { index: 0, active: false } : { index: t.index + 1, active: true });
export const tourSkip = (): Tour => TOUR_IDLE;

// The tour starts once, the first time the user lands on Remote connected.
export function shouldStartTour(p: { tourDone: boolean; connected: boolean; onRemote: boolean; modalOpen: boolean; active: boolean }): boolean {
  return !p.tourDone && p.connected && p.onRemote && !p.modalOpen && !p.active;
}

// Callout placement: below the target if there is room, else above.
export type Rect = { x: number; y: number; w: number; h: number };
export function calloutPlacement(target: Rect, screenH: number, calloutH: number, margin = 14): { top: number; below: boolean } {
  const below = target.y + target.h + margin + calloutH <= screenH - 24;
  if (below) return { top: target.y + target.h + margin, below: true };
  const top = target.y - margin - calloutH;
  return top >= 24 ? { top, below: false } : { top: Math.max(24, (screenH - calloutH) / 2), below: true };
}
