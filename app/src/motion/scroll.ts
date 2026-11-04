// Smooth scrolling from the phone (docs/spec-v3.md 3, 6). Pure, node --test.
//
// Units (Mac contract, spec section 3): with `phase`, dy is fractional
// POINTS, positive = content scrolls down. Without `phase`, dy is whole
// notches (12 pt) as before. Phases: begin (finger down), move (dragging),
// end (finger up, no fling), momentum (coasting after a flick). A fling is
// over with a zero-delta `momentum`, or a new `begin`.

export type ScrollPhase = 'begin' | 'move' | 'end' | 'momentum';

export const NOTCH_PT = 12; // one wheel notch on the Mac
export const SCROLL_STEP_PX = 14; // finger travel per notch at speed 1 (the old feel)
export const PT_PER_PX = NOTCH_PT / SCROLL_STEP_PX;
export const FRAME_MS = 16;
export const MOMENTUM_DECAY = 0.95; // per frame
export const MOMENTUM_MIN = 0.5; // points per frame: below this, stop
export const MOMENTUM_MAX = 150; // points per frame, caps a wild flick

const round2 = (v: number) => Math.round(v * 100) / 100 || 0;

// Finger moved `fingerUpPx` (positive = finger moved up the screen) -> points.
// Natural (default, like a trackpad): finger up = content scrolls down.
export function fingerToScroll(fingerUpPx: number, natural: boolean, speed: number): number {
  return (natural ? 1 : -1) * fingerUpPx * speed * PT_PER_PX;
}

// Sum of deltas since the last frame; take() returns it (2 decimals) or null.
export class ScrollCoalescer {
  private acc = 0;

  add(dy: number): void {
    this.acc += dy;
  }

  take(): number | null {
    const v = round2(this.acc);
    if (v === 0) return null; // keep sub-0.005 crumbs for the next frame
    this.acc -= v;
    return v;
  }

  // Whatever is left, even tiny (finger up).
  drain(): number {
    const v = round2(this.acc);
    this.acc = 0;
    return v;
  }
}

// Velocity in points per frame from the last ~80 ms of drag.
export class VelocityTracker {
  private samples: { t: number; dy: number }[] = [];
  private readonly windowMs: number;

  constructor(windowMs = 80) {
    this.windowMs = windowMs;
  }

  reset(): void {
    this.samples = [];
  }

  add(dy: number, t: number): void {
    this.samples.push({ t, dy });
    while (this.samples.length && t - this.samples[0].t > this.windowMs) this.samples.shift();
  }

  // `now` = release time: a finger that stopped before letting go has no velocity.
  perFrame(now: number): number {
    const recent = this.samples.filter((s) => now - s.t <= this.windowMs);
    if (recent.length < 2) return 0;
    const span = Math.max(FRAME_MS, now - recent[0].t);
    const sum = recent.slice(1).reduce((a, s) => a + s.dy, 0);
    return (sum / span) * FRAME_MS;
  }
}

// Momentum deltas, one per frame: v, v*decay, ... until |v| < min.
export function momentumSteps(v0: number, decay = MOMENTUM_DECAY, min = MOMENTUM_MIN, max = MOMENTUM_MAX): number[] {
  const out: number[] = [];
  let v = Math.max(-max, Math.min(max, v0));
  while (Math.abs(v) >= min && out.length < 600) {
    out.push(round2(v));
    v *= decay;
  }
  return out;
}
