/// <reference types="node" />
// Run: npm test  (Node's built-in runner, TypeScript stripped natively)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MotionEngine, accelGain, applyDeadzone, DEFAULT_SETTINGS, type GyroSample } from './engine.ts';

const HZ = 60;
function run(engine: MotionEngine, w: { x?: number; z?: number }, seconds: number, active = true) {
  let dx = 0;
  let dy = 0;
  const n = Math.round(seconds * HZ);
  for (let i = 0; i <= n; i++) {
    const s: GyroSample = { x: w.x ?? 0, y: 0, z: w.z ?? 0, timestamp: i / HZ };
    const out = engine.update(s, active);
    dx += out.dx;
    dy += out.dy;
  }
  return { dx, dy };
}

test('soft dead zone squashes tremor but keeps slow turns', () => {
  assert.equal(applyDeadzone(0, 0.03), 0);
  assert.ok(Math.abs(applyDeadzone(0.005, 0.03)) < 0.0002); // tremor ~ gone
  assert.ok(applyDeadzone(0.03, 0.03) > 0.014); // slow turn still moves
  assert.ok(Math.abs(applyDeadzone(-0.03, 0.03) + applyDeadzone(0.03, 0.03)) < 1e-12);
  assert.ok(applyDeadzone(1, 0.03) > 0.999); // fast turn ~ unchanged
  assert.equal(applyDeadzone(0.4, 0), 0.4);
});

test('turning right moves cursor right', () => {
  const r = run(new MotionEngine(), { z: -1 }, 0.5);
  assert.ok(r.dx > 0, `dx=${r.dx}`);
  assert.equal(r.dy, 0);
});

test('tipping the top up moves cursor up', () => {
  const r = run(new MotionEngine(), { x: 1 }, 0.5);
  assert.ok(r.dy < 0, `dy=${r.dy}`);
  assert.equal(r.dx, 0);
});

test('distance matches sensitivity (pixels per radian)', () => {
  // 0.5 rad turned at 1 rad/s; dead zone and filter warm-up cost a little.
  // Linear mapping = acceleration off.
  const r = run(new MotionEngine({ ...DEFAULT_SETTINGS, acceleration: 0 }), { z: -1 }, 0.5);
  const ideal = 0.5 * DEFAULT_SETTINGS.sensitivity;
  assert.ok(r.dx > ideal * 0.85 && r.dx <= ideal, `dx=${r.dx} ideal=${ideal}`);
});

test('slow steady turn still moves (sub-pixel accumulation)', () => {
  // 0.05 rad/s gives under 1 px per frame but must add up.
  const r = run(new MotionEngine(), { z: -0.05 }, 2);
  assert.ok(r.dx >= 40, `dx=${r.dx}`);
});

test('no movement while clutch released', () => {
  const r = run(new MotionEngine(), { z: -2, x: 2 }, 1, false);
  assert.deepEqual(r, { dx: 0, dy: 0 });
});

test('hand tremor inside dead zone does not move cursor', () => {
  // Moves are fractional now (the Mac keeps sub-pixel position): tremor may
  // emit tiny moves, but the cursor must stay within one point of where it was.
  const e = new MotionEngine();
  let x = 0;
  let y = 0;
  let worst = 0;
  for (let i = 0; i < 120; i++) {
    const w = 0.02 * Math.sin(i * 0.9);
    const r = e.update({ x: w, y: 0, z: w, timestamp: i / HZ }, true);
    x += r.dx;
    y += r.dy;
    worst = Math.max(worst, Math.abs(x), Math.abs(y));
  }
  assert.ok(worst < 1, `worst=${worst}`);
});

test('long gap between samples is ignored', () => {
  const e = new MotionEngine();
  e.update({ x: 0, y: 0, z: -3, timestamp: 0 }, true);
  assert.deepEqual(e.update({ x: 0, y: 0, z: -3, timestamp: 2 }, true), { dx: 0, dy: 0 });
});

test('invert flips direction', () => {
  const e = new MotionEngine({ ...DEFAULT_SETTINGS, invertX: true, invertY: true });
  const r = run(e, { z: -1, x: 1 }, 0.3);
  assert.ok(r.dx < 0 && r.dy > 0, JSON.stringify(r));
});

test('calibrated constant gyro bias produces no movement', () => {
  const e = new MotionEngine({ ...DEFAULT_SETTINGS, biasX: 0.2, biasZ: -0.3 });
  const r = run(e, { x: 0.2, z: -0.3 }, 1);
  assert.deepEqual(r, { dx: 0, dy: 0 });
});

test('a slow sample rate (lost samples) still moves', () => {
  // 12 Hz delivery = 83 ms between samples; the old 50 ms cut made this 0.
  const e = new MotionEngine();
  let dx = 0;
  for (let i = 0; i <= 12; i++) dx += e.update({ x: 0, y: 0, z: -1, timestamp: i / 12 }, true).dx;
  assert.ok(dx > 500, `dx=${dx}`);
});

test('acceleration gain is 1 at rest and capped at 1 + 2a', () => {
  assert.equal(accelGain(0, 0.4), 1);
  assert.ok(Math.abs(accelGain(0.01, 0.4) - 1) < 0.003); // slow aiming ~unchanged
  assert.ok(Math.abs(accelGain(1.5, 0.4) - 1.4) < 1e-12);
  assert.equal(accelGain(10, 0.4), 1.8);
  assert.equal(accelGain(-3, 1), 3);
  assert.equal(accelGain(2, 0), 1);
});

test('acceleration leaves slow turns alone and speeds up fast ones', () => {
  const off = { ...DEFAULT_SETTINGS, acceleration: 0 };
  const on = { ...DEFAULT_SETTINGS, acceleration: 0.4 };
  const slowOff = run(new MotionEngine(off), { z: -0.05 }, 2).dx;
  const slowOn = run(new MotionEngine(on), { z: -0.05 }, 2).dx;
  assert.ok(Math.abs(slowOn - slowOff) <= Math.max(2, slowOff * 0.03), `slow off=${slowOff} on=${slowOn}`);
  const fastOff = run(new MotionEngine(off), { z: -3 }, 0.3).dx;
  const fastOn = run(new MotionEngine(on), { z: -3 }, 0.3).dx;
  assert.ok(fastOn > fastOff * 1.5, `fast off=${fastOff} on=${fastOn}`);
});

test('vertical motion uses sensitivityY', () => {
  const base = { ...DEFAULT_SETTINGS, acceleration: 0 };
  const a = run(new MotionEngine({ ...base, sensitivityY: 1000 }), { x: 1 }, 0.5).dy;
  const b = run(new MotionEngine({ ...base, sensitivityY: 2000 }), { x: 1 }, 0.5).dy;
  assert.ok(a < 0 && Math.abs(b / a - 2) < 0.02, `a=${a} b=${b}`);
});

test('moves are fractional, rounded to 2 decimals', () => {
  const e = new MotionEngine({ ...DEFAULT_SETTINGS, acceleration: 0, deadzone: 0 });
  let sawFraction = false;
  for (let i = 0; i <= 30; i++) {
    const r = e.update({ x: 0, y: 0, z: -0.05, timestamp: i / 100 }, true);
    assert.equal(Math.round(r.dx * 100) / 100, r.dx);
    if (r.dx > 0 && r.dx < 1) sawFraction = true;
  }
  assert.ok(sawFraction, 'slow turn should give sub-point moves, not truncated zeros');
});
