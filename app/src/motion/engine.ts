// Turns gyroscope samples into fractional cursor deltas (points, 2 decimals).
// The Mac keeps the sub-pixel position and paces the moves to the display.
// Pure logic, no React Native imports, so it runs under `node --test`.
//
// Phone held like a TV remote: portrait, top edge pointing at the screen,
// display facing up. Turning left/right = rotation about device Z (yaw),
// tipping the top up/down = rotation about device X (pitch).

export type GyroSample = { x: number; y: number; z: number; timestamp: number }; // rad/s, seconds

export type MotionSettings = {
  sensitivity: number; // pixels per radian turned, horizontal
  sensitivityY: number; // pixels per radian, vertical (4-corner calibration)
  acceleration: number; // 0 = off .. 1; extra gain for fast turns
  deadzone: number; // rad/s; slower rotation is treated as hand tremor
  invertX: boolean;
  invertY: boolean;
  smoothing: number; // One Euro min cutoff in Hz; lower = smoother but laggier
  biasX: number;
  biasY: number;
  biasZ: number;
};

export const DEFAULT_SETTINGS: MotionSettings = {
  sensitivity: 1400,
  sensitivityY: 1400,
  acceleration: 0.4,
  deadzone: 0.02,
  invertX: false,
  invertY: false,
  smoothing: 1.0,
  biasX: 0,
  biasY: 0,
  biasZ: 0,
};

// One Euro filter (Casiez et al., 2012): smooth when slow, responsive when fast.
export class OneEuroFilter {
  private x: number | null = null;
  private dx = 0;

  minCutoff: number;
  beta: number;
  dCutoff: number;

  constructor(minCutoff = 1.0, beta = 0.02, dCutoff = 1.0) {
    this.minCutoff = minCutoff;
    this.beta = beta;
    this.dCutoff = dCutoff;
  }

  private static alpha(cutoff: number, dt: number): number {
    const tau = 1 / (2 * Math.PI * cutoff);
    return 1 / (1 + tau / dt);
  }

  filter(value: number, dt: number): number {
    if (this.x === null || dt <= 0) {
      this.x = value;
      return value;
    }
    const rawDx = (value - this.x) / dt;
    const ad = OneEuroFilter.alpha(this.dCutoff, dt);
    this.dx = ad * rawDx + (1 - ad) * this.dx;
    const cutoff = this.minCutoff + this.beta * Math.abs(this.dx);
    const a = OneEuroFilter.alpha(cutoff, dt);
    this.x = a * value + (1 - a) * this.x;
    return this.x;
  }

  reset(): void {
    this.x = null;
    this.dx = 0;
  }
}

// Soft dead zone: w * w^2 / (w^2 + dz^2). Tremor well under `deadzone` is
// squashed toward 0, but slow deliberate turns still move (no hard cut that
// swallowed every turn slower than the threshold), and fast turns pass
// almost unchanged.
export function applyDeadzone(w: number, deadzone: number): number {
  if (deadzone <= 0) return w;
  const w2 = w * w;
  return (w * w2) / (w2 + deadzone * deadzone);
}

// Pointer acceleration: 1 at rest so slow aiming keeps its precision, up to
// 1 + 2 * acceleration for turns at 3 rad/s and faster.
export const ACCEL_REF = 1.5; // rad/s
export function accelGain(omega: number, acceleration: number): number {
  if (!(acceleration > 0)) return 1;
  return 1 + acceleration * Math.min(Math.abs(omega) / ACCEL_REF, 2);
}

const round2 = (v: number) => Math.round(v * 100) / 100 || 0; // || 0 drops -0

// Below this (points) a move is not worth a message.
export const MIN_MOVE = 0.01;

// A gap longer than this (app suspended, sensor restart) is not motion. It
// used to be 50 ms: at 60 Hz that is only 3 lost samples, and a busy JS
// thread or a second CoreMotion client can push the delivered rate under
// 20 Hz, which silently turned every sample into a zero move.
export const MAX_DT = 0.2;

export class MotionEngine {
  private fx = new OneEuroFilter();
  private fy = new OneEuroFilter();
  private lastT: number | null = null;
  // Reused result: update() runs at 100 Hz and must not allocate.
  private readonly out = { dx: 0, dy: 0 };

  settings: MotionSettings;

  constructor(settings: MotionSettings = DEFAULT_SETTINGS) {
    this.settings = settings;
  }

  // `active` = clutch engaged. Filters keep running while inactive so the
  // cursor does not lurch when the clutch is pressed again.
  // The returned object is reused by the next call: read it, don't keep it.
  update(s: GyroSample, active: boolean): { readonly dx: number; readonly dy: number } {
    const out = this.out;
    out.dx = 0;
    out.dy = 0;
    const dt = this.lastT === null ? 0 : s.timestamp - this.lastT;
    this.lastT = s.timestamp;
    if (dt <= 0 || dt > MAX_DT) return out;

    const { sensitivity, deadzone, invertX, invertY, smoothing, acceleration } = this.settings;
    const sensitivityY = this.settings.sensitivityY ?? sensitivity;
    this.fx.minCutoff = smoothing;
    this.fy.minCutoff = smoothing;

    // Right-hand rule: turning right = -Z, tipping the top up = +X.
    const yaw = this.fx.filter(-(s.z - this.settings.biasZ), dt);
    const pitch = this.fy.filter(s.x - this.settings.biasX, dt);

    if (!active) return out;

    // Screen Y grows downward, tipping the top up must move the cursor up.
    const gain = accelGain(Math.hypot(yaw, pitch), acceleration ?? 0);
    const vx = applyDeadzone(yaw, deadzone) * gain * (invertX ? -1 : 1);
    const vy = -applyDeadzone(pitch, deadzone) * gain * (invertY ? -1 : 1);

    out.dx = round2(vx * dt * sensitivity);
    out.dy = round2(vy * dt * sensitivityY);
    return out;
  }

  reset(): void {
    this.fx.reset();
    this.fy.reset();
    this.lastT = null;
  }
}
