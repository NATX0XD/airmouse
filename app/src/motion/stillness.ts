import type { GyroSample } from './engine';

// "Hold your iPhone to the screen" step: the phone counts as still while the
// gyro magnitude stays under `threshold`. `holdSeconds` of uninterrupted still
// samples completes the step; any movement drains progress back to zero.
// Pure logic so it runs under `node --test`.

export type StillnessState = { progress: number; still: boolean; done: boolean };
export type StillnessOptions = { threshold?: number; holdSeconds?: number };

export class StillnessDetector {
  private readonly threshold: number;
  private readonly holdSeconds: number;
  private startedAt: number | null = null;
  private samples: GyroSample[] = [];
  private finished = false;

  constructor(options: StillnessOptions = {}) {
    this.threshold = options.threshold ?? 0.1;
    this.holdSeconds = options.holdSeconds ?? 2.0;
  }

  update(s: GyroSample): StillnessState {
    if (this.finished) return { progress: 1, still: true, done: true };
    const magnitude = Math.hypot(s.x, s.y, s.z);
    if (!(magnitude < this.threshold)) {
      this.startedAt = null;
      this.samples = [];
      return { progress: 0, still: false, done: false };
    }
    if (this.startedAt === null) this.startedAt = s.timestamp;
    this.samples.push(s);
    const progress = Math.min(1, (s.timestamp - this.startedAt) / this.holdSeconds);
    if (progress >= 1) this.finished = true;
    return { progress, still: true, done: this.finished };
  }

  get done(): boolean {
    return this.finished;
  }

  // Samples of the current still run (used to compute the gyro bias).
  stillSamples(): GyroSample[] {
    return [...this.samples];
  }

  reset(): void {
    this.startedAt = null;
    this.samples = [];
    this.finished = false;
  }
}

// Rate limiter for the ~10 Hz `calib place` messages.
export function shouldEmit(now: number, last: number | null, intervalMs: number): boolean {
  return last === null || now - last >= intervalMs;
}
