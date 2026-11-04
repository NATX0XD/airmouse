import type { GyroSample } from './engine';
import { StillnessDetector, type StillnessOptions } from './stillness.ts';

// Calibration step 1 v2 (docs/spec-v3.md 4a.1): the phone is "placed" only
// while it is
//   - near: proximity sensor covered (screen against the display),
//   - upright: gravity mostly along device Y, i.e. against a vertical-ish
//     display, not lying on a desk,
//   - still: gyro magnitude under the threshold,
// for `holdSeconds` in a row. Any of the three failing resets progress.
// Pure logic so it runs under `node --test`.

export type Accel = { x: number; y: number; z: number }; // g (iOS reports in g)

export const UPRIGHT_MIN_Y = 0.75;
export const UPRIGHT_MAX_Z = 0.6;

export function isUpright(a: Accel | null): boolean {
  if (!a) return false;
  return Math.abs(a.y) > UPRIGHT_MIN_Y && Math.abs(a.z) < UPRIGHT_MAX_Z;
}

export type PlacementState = { progress: number; still: boolean; near: boolean; upright: boolean; done: boolean };

export class PlacementDetector {
  private readonly stillness: StillnessDetector;

  constructor(options: StillnessOptions = {}) {
    this.stillness = new StillnessDetector(options);
  }

  update(s: GyroSample, ctx: { near: boolean; accel: Accel | null }): PlacementState {
    const upright = isUpright(ctx.accel);
    const near = ctx.near;
    if (!near || !upright) {
      // A finished placement stays finished (the user lifts the phone after it).
      if (this.stillness.done) return { progress: 1, still: true, near, upright, done: true };
      this.stillness.reset();
      return { progress: 0, still: false, near, upright, done: false };
    }
    const r = this.stillness.update(s);
    return { ...r, near, upright };
  }

  // Gyro samples of the current placed-and-still run (for the bias).
  stillSamples(): GyroSample[] {
    return this.stillness.stillSamples();
  }

  reset(): void {
    this.stillness.reset();
  }
}

// What the phone (and the Mac overlay) should ask for next.
export type PlacementHint = 'bring' | 'upright' | 'still' | 'holding' | 'done';
export function placementHint(s: PlacementState): PlacementHint {
  if (s.done) return 'done';
  if (!s.near) return 'bring';
  if (!s.upright) return 'upright';
  return s.still ? 'holding' : 'still';
}
