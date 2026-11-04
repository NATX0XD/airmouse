// Pure helpers for the "From Sensor to Cursor" diagrams (kept free of React so node tests can run them).

export const EXAMPLE_DEG_PER_SEC = 29;
export const EXAMPLE_DOTS_PER_DEG = 24;
export const SAMPLE_MS = 10;

/** Dots the cursor moves for a turn at `degPerSec` held for `ms`, at `dotsPerDeg` calibration. */
export function dotsMoved(degPerSec: number, ms: number, dotsPerDeg: number): number {
  return degPerSec * (ms / 1000) * dotsPerDeg;
}

/** Deterministic pseudo-noise in [-1, 1] so the jitter diagram looks the same every frame. */
export function wobble(x: number): number {
  return (Math.sin(x * 12.9898) * 0.6 + Math.sin(x * 4.1414 + 1.3) * 0.4);
}

/** A slow move with a quick flick near the middle (0..1 input, 0..1 output). */
export function intent(u: number): number {
  const slow = 0.5 + 0.18 * Math.sin(u * Math.PI * 2);
  const flick = 1 / (1 + Math.exp(-(u - 0.62) * 40));
  return slow * 0.55 + flick * 0.35;
}

/** Raw sensor line: intent plus wobble. */
export function rawLine(u: number, shake: number, phase = 0): number {
  return intent(u) + wobble(u * 40 + phase) * shake;
}

/** Filtered line: follows intent, wobble squashed to a sliver. */
export function smoothLine(u: number, shake: number, phase = 0): number {
  return intent(u) + wobble(u * 40 + phase) * shake * 0.08;
}

/** Position 0..1 along a lane for bursty arrivals: notes bunch together. */
export function burstPos(i: number, phase: number): number {
  const group = Math.floor(i / 3);
  const within = i % 3;
  return ((group * 0.34 + within * 0.035 + phase) % 1 + 1) % 1;
}
