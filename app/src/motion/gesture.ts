import type { GyroSample } from './engine';

export type FlickDirection = 'left' | 'right';
export type FlickOptions = { threshold?: number; maxDurationMs?: number; refractoryMs?: number };

// A short threshold crossing is easier to tune on a real phone than a
// distance integration: it ignores slow turns and the return swing is muted.
export class FlickDetector {
  private startedAt: number | null = null;
  private refractoryUntil = 0;
  private readonly threshold: number;
  private readonly maxDurationMs: number;
  private readonly refractoryMs: number;

  constructor(options: FlickOptions = {}) {
    this.threshold = options.threshold ?? 4;
    this.maxDurationMs = options.maxDurationMs ?? 220;
    this.refractoryMs = options.refractoryMs ?? 600;
  }

  update(sample: GyroSample): FlickDirection | null {
    const now = sample.timestamp * 1000;
    if (now < this.refractoryUntil) return null;
    if (Math.abs(sample.z) < this.threshold) {
      if (this.startedAt !== null) {
        const duration = now - this.startedAt;
        const direction: FlickDirection = this.startedZ > 0 ? 'left' : 'right';
        this.startedAt = null;
        if (duration <= this.maxDurationMs) {
          this.refractoryUntil = now + this.refractoryMs;
          return direction;
        }
      }
      return null;
    }
    if (this.startedAt === null) {
      this.startedAt = now;
      this.startedZ = sample.z;
    }
    return null;
  }

  private startedZ = 0;

  reset(): void {
    this.startedAt = null;
    this.refractoryUntil = 0;
  }
}
