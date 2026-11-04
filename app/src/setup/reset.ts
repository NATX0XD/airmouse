import { FLAG_KEYS } from './onboarding.ts';

// "Reset AirMouse…" (Settings): back to a first launch. Pure, node --test.
//
// Everything the app keeps lives in AsyncStorage (the app writes no files):
// settings (saved Macs, calibration incl. calibratedV3, speed, scroll…),
// onboarding flags and the screenshot preview query. All keys are erased,
// known ones explicitly so a failing getAllKeys can't leave them behind.
// In-memory state (engine, pause latch, transport) is reset by remounting
// the app root (App.tsx). iOS permissions can't be revoked by an app.

export const SETTINGS_KEY = 'airmouse.settings.v1';
export const PREVIEW_KEY = 'airmouse.preview';
export const KNOWN_KEYS: readonly string[] = [SETTINGS_KEY, PREVIEW_KEY, ...Object.values(FLAG_KEYS)];

export const RESET_ALERT = {
  title: 'Reset AirMouse?',
  message: 'This erases calibration, saved Macs, settings and onboarding progress. AirMouse will start over with Welcome.',
  confirm: 'Reset',
} as const;
export const RESET_FOOTNOTE = 'System permissions stay granted; change them in the Settings app.';

export type KeyValueStore = {
  getAllKeys(): Promise<readonly string[]>;
  multiRemove(keys: string[]): Promise<void>;
};

// Returns the keys removed.
export async function eraseAll(store: KeyValueStore): Promise<string[]> {
  let found: readonly string[] = [];
  try {
    found = await store.getAllKeys();
  } catch {
    // fall back to the known keys
  }
  const keys = [...new Set([...KNOWN_KEYS, ...found])];
  await store.multiRemove(keys);
  return keys;
}
