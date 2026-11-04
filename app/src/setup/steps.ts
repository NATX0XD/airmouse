// Permission Setup stepper (docs/spec-v3.md 2a). Pure, no React Native.

export type PermissionId = 'localNetwork' | 'bluetooth' | 'camera' | 'motion';
// unavailable = the device can't do it at all (e.g. no gyro in the Simulator).
export type PermissionStatus = 'unknown' | 'granted' | 'denied' | 'unavailable';
export type Statuses = Record<PermissionId, PermissionStatus>;

export type StepDef = { id: PermissionId; required: boolean; automatic: boolean };

export const STEPS: StepDef[] = [
  { id: 'localNetwork', required: true, automatic: false }, // needed for Wi-Fi
  { id: 'bluetooth', required: false, automatic: false },
  { id: 'camera', required: false, automatic: false }, // QR code
  { id: 'motion', required: false, automatic: true }, // no prompt on iOS; shown as a check
];

export const INITIAL_STATUSES: Statuses = { localNetwork: 'unknown', bluetooth: 'unknown', camera: 'unknown', motion: 'unknown' };

export type Primary = 'request' | 'openSettings' | 'continue' | 'wait';
export type StepActions = { primary: Primary; canSkip: boolean };

export function actionsFor(step: StepDef, status: PermissionStatus): StepActions {
  if (status === 'granted' || status === 'unavailable') return { primary: 'continue', canSkip: false };
  if (step.automatic) return { primary: 'wait', canSkip: true };
  // A denied permission can only be changed in Settings. Never trap the user:
  // even the required one can be skipped once denied (Bluetooth still works).
  if (status === 'denied') return { primary: 'openSettings', canSkip: true };
  return { primary: 'request', canSkip: !step.required };
}

export type SetupState = { index: number; done: boolean };

export function next(state: SetupState): SetupState {
  const index = state.index + 1;
  return index >= STEPS.length ? { index: STEPS.length - 1, done: true } : { index, done: false };
}

export function back(state: SetupState): SetupState {
  return { index: Math.max(0, state.index - 1), done: false };
}

export function startAt(id: PermissionId): SetupState {
  return { index: Math.max(0, STEPS.findIndex((s) => s.id === id)), done: false };
}

// Permissions worth a warning row on the main screens.
export function missing(statuses: Statuses): PermissionId[] {
  return STEPS.filter((s) => statuses[s.id] === 'denied').map((s) => s.id);
}

export function stepCompleted(step: StepDef, status: PermissionStatus): boolean {
  return status === 'granted' || status === 'unavailable';
}
