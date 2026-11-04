import { DEFAULT_SETTINGS, type MotionSettings } from '../motion/engine.ts';

// Per-Mac "has this phone been calibrated against it" + settings migration.
// Pure, runs under node --test.

export type ScreenId = { w: number; h: number; name?: string };

// A display is identified by its name and size in points.
export function screenKey(s: ScreenId): string {
  return `${(s.name ?? '').trim()}|${Math.round(s.w)}x${Math.round(s.h)}`;
}

// Stored motion settings from before v3 lack sensitivityY / acceleration.
export function migrateMotion(saved: Partial<MotionSettings> | undefined): MotionSettings {
  const m = { ...DEFAULT_SETTINGS, ...saved };
  if (!saved || typeof saved.sensitivityY !== 'number' || !(saved.sensitivityY > 0)) m.sensitivityY = m.sensitivity;
  if (typeof m.acceleration !== 'number' || !Number.isFinite(m.acceleration)) m.acceleration = DEFAULT_SETTINGS.acceleration;
  m.acceleration = Math.min(1, Math.max(0, m.acceleration));
  return m;
}

// Only v3 (centre + 4 corners) calibrations count, stored in `calibratedV3`.
// Older 2-dot results (calibratedAt, the v3-beta `calibratedScreens`) are
// ignored on purpose, so every display is offered the new flow once.
export function readCalibrated(list: unknown): string[] {
  return Array.isArray(list) ? list.filter((k): k is string => typeof k === 'string') : [];
}

export function markCalibrated(list: readonly string[], s: ScreenId): string[] {
  const k = screenKey(s);
  return list.includes(k) ? [...list] : [...list, k];
}

// Show "Calibrate for Accurate Pointing" on Remote?
export function shouldPromptCalibration(p: {
  connected: boolean;
  screen: ScreenId | null; // what the Mac reported this session
  calibrated: readonly string[];
  dismissed: boolean; // "Later" this session
  busy: boolean; // a modal / calibration is on screen
}): boolean {
  if (!p.connected || !p.screen || p.dismissed || p.busy) return false;
  return !p.calibrated.includes(screenKey(p.screen));
}
