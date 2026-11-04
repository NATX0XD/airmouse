import type { PointerMode } from '../settings';

// Pure pointer rules, shared by useAirMouse and RemoteScreen (node --test).

// Hold to Point: the cursor moves only while a finger is on the pad.
// Always On: the cursor always moves; a finger on the pad pauses it.
export function pointerActive(mode: PointerMode, touching: boolean): boolean {
  return mode === 'hold' ? touching : !touching;
}

export const TAP_MS = 200; // a shorter touch on the pad = left click

export function isTap(downAt: number, upAt: number): boolean {
  return upAt - downAt < TAP_MS;
}
