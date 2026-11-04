import { MAX_DT, type GyroSample, type MotionSettings } from './engine.ts';

export type BiasResult = { ok: true; biasX: number; biasY: number; biasZ: number } | { ok: false; reason: 'moved' };

export function calibrateBias(samples: GyroSample[], maxSpread = 0.05): BiasResult {
  if (samples.length === 0) return { ok: false, reason: 'moved' };
  const mean = (key: keyof GyroSample) => samples.reduce((sum, s) => sum + Number(s[key]), 0) / samples.length;
  const biasX = mean('x');
  const biasY = mean('y');
  const biasZ = mean('z');
  const moved = samples.some((s) => Math.abs(s.x - biasX) > maxSpread || Math.abs(s.y - biasY) > maxSpread || Math.abs(s.z - biasZ) > maxSpread);
  return moved ? { ok: false, reason: 'moved' } : { ok: true, biasX, biasY, biasZ };
}

export function integrateYaw(samples: GyroSample[], settings: MotionSettings): number {
  let angle = 0;
  for (let i = 1; i < samples.length; i++) {
    const dt = samples[i].timestamp - samples[i - 1].timestamp;
    if (dt > 0 && dt <= MAX_DT) angle += -(samples[i - 1].z - settings.biasZ + samples[i].z - settings.biasZ) * dt / 2;
  }
  return angle;
}

// Speed range (points per radian). The upper end matters: the dots are 80 %
// of the display apart, so a 2560 pt wide 69 cm display seen from 1.5 m is
// only ~21 degrees of turn = ~5600 pt/rad. 4000 forced a clamp there.
export const SENS_MIN = 300;
export const SENS_MAX = 8000;

export function sensitivityFromAngle(screenWidth: number, angle: number, current: number, min = SENS_MIN, max = SENS_MAX): number | null {
  if (Math.abs(angle) < 0.1) return null;
  return Math.min(max, Math.max(min, screenWidth / Math.abs(angle)));
}

export const toDegrees = (rad: number) => (Math.abs(rad) * 180) / Math.PI;

// Calibration step 3 result (docs/spec-v3.md 4a.3): a result that would hit
// the clamp is not saved, the user is asked to retry instead.
export type TurnResult =
  | { ok: true; sensitivity: number; degrees: number }
  | { ok: false; reason: 'small' | 'large'; degrees: number };

export function evaluateTurn(distance: number, angle: number, min = SENS_MIN, max = SENS_MAX): TurnResult {
  const degrees = toDegrees(angle);
  const a = Math.abs(angle);
  if (!(a > 0) || !Number.isFinite(a) || distance <= 0) return { ok: false, reason: 'small', degrees: Number.isFinite(degrees) ? degrees : 0 };
  const raw = distance / a;
  if (raw > max) return { ok: false, reason: 'small', degrees };
  if (raw < min) return { ok: false, reason: 'large', degrees };
  return { ok: true, sensitivity: Math.round(raw), degrees };
}

// ---------- Calibration v3: centre + 4 corners (docs/spec-v3.md 4a) ----------

export type CornerTarget = 'center' | 'tl' | 'tr' | 'br' | 'bl';
export const CALIB_TARGETS: readonly CornerTarget[] = ['center', 'tl', 'tr', 'br', 'bl'];
export const TARGET_NAMES: Record<CornerTarget, string> = { center: 'Center', tl: 'Top Left', tr: 'Top Right', br: 'Bottom Right', bl: 'Bottom Left' };
export const CORNER_INSET = 0.08; // corners sit 8 % in from each edge
export const CORNER_SPAN = 1 - 2 * CORNER_INSET; // 0.84 of the width / height between corners

// Target position as a fraction of the display (0..1, +y down).
export function targetFraction(t: CornerTarget): { x: number; y: number } {
  const lo = CORNER_INSET;
  const hi = 1 - CORNER_INSET;
  switch (t) {
    case 'center':
      return { x: 0.5, y: 0.5 };
    case 'tl':
      return { x: lo, y: lo };
    case 'tr':
      return { x: hi, y: lo };
    case 'br':
      return { x: hi, y: hi };
    case 'bl':
      return { x: lo, y: hi };
  }
}

export type Angles = { yaw: number; pitch: number }; // rad, since the centre tap

// Bias-corrected yaw (turn right = +) and pitch (top up = +), trapezoid rule,
// same sign conventions as MotionEngine. Gaps over MAX_DT are skipped.
export class AngleIntegrator {
  yaw = 0;
  pitch = 0;
  private last: GyroSample | null = null;

  reset(): void {
    this.yaw = 0;
    this.pitch = 0;
    this.last = null;
  }

  add(s: GyroSample, bias: { biasX: number; biasZ: number }): void {
    const prev = this.last;
    this.last = s;
    if (!prev) return;
    const dt = s.timestamp - prev.timestamp;
    if (!(dt > 0) || dt > MAX_DT) return;
    this.yaw += (-(prev.z - bias.biasZ) - (s.z - bias.biasZ)) * dt / 2;
    this.pitch += (prev.x - bias.biasX + s.x - bias.biasX) * dt / 2;
  }

  snapshot(): Angles {
    return { yaw: this.yaw, pitch: this.pitch };
  }
}

export type Corners = Record<'tl' | 'tr' | 'br' | 'bl', Angles>;

export type CornerResult =
  | { ok: true; sensitivity: number; sensitivityY: number; degreesX: number; degreesY: number }
  | { ok: false; axis: 'x' | 'y'; reason: 'small' | 'large'; degreesX: number; degreesY: number };

// sensX = 0.84 w / mean(|yaw tr - tl|, |yaw br - bl|)
// sensY = 0.84 h / mean(|pitch bl - tl|, |pitch br - tr|)
// Each axis keeps the 2-dot rule: a result that would clamp asks for a retry.
export function evaluateCorners(c: Corners, w: number, h: number, min = SENS_MIN, max = SENS_MAX): CornerResult {
  const spanX = (Math.abs(c.tr.yaw - c.tl.yaw) + Math.abs(c.br.yaw - c.bl.yaw)) / 2;
  const spanY = (Math.abs(c.bl.pitch - c.tl.pitch) + Math.abs(c.br.pitch - c.tr.pitch)) / 2;
  const x = evaluateTurn(CORNER_SPAN * w, spanX, min, max);
  const y = evaluateTurn(CORNER_SPAN * h, spanY, min, max);
  const degreesX = x.degrees;
  const degreesY = y.degrees;
  if (!x.ok) return { ok: false, axis: 'x', reason: x.reason, degreesX, degreesY };
  if (!y.ok) return { ok: false, axis: 'y', reason: y.reason, degreesX, degreesY };
  return { ok: true, sensitivity: x.sensitivity, sensitivityY: y.sensitivity, degreesX, degreesY };
}

// Speed slider: move horizontal speed to `v`, keep the calibrated X:Y ratio.
export function scaleSpeed(m: Pick<MotionSettings, 'sensitivity' | 'sensitivityY'>, v: number, min = SENS_MIN, max = SENS_MAX) {
  const clamp = (n: number) => Math.round(Math.min(max, Math.max(min, n)));
  const ratio = m.sensitivity > 0 && m.sensitivityY > 0 ? m.sensitivityY / m.sensitivity : 1;
  return { sensitivity: clamp(v), sensitivityY: clamp(v * ratio) };
}
