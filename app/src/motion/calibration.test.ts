import assert from 'node:assert/strict';
import test from 'node:test';
import { calibrateBias, integrateYaw, sensitivityFromAngle } from './calibration.ts';
import { DEFAULT_SETTINGS } from './engine.ts';

const sample = (x: number, z: number, timestamp: number) => ({ x, y: 0, z, timestamp });
test('bias calibration averages still samples and rejects movement', () => {
  const ok = calibrateBias([sample(0.01, -0.02, 0), sample(0.02, -0.01, 0.1)]);
  assert.equal(ok.ok, true);
  if (ok.ok) assert.deepEqual([ok.biasX, ok.biasZ], [0.015, -0.015]);
  assert.equal(calibrateBias([sample(0, 0, 0), sample(0.2, 0, 0.1)]).ok, false);
});
test('integrates bias-corrected yaw and derives sensitivity', () => {
  const settings = { ...DEFAULT_SETTINGS, biasZ: 0.1 };
  const samples = Array.from({ length: 11 }, (_, i) => sample(0, -1.1, i * 0.05));
  const angle = integrateYaw(samples, settings);
  assert.ok(Math.abs(angle - 0.6) < 1e-9);
  assert.ok(Math.abs(sensitivityFromAngle(1000, angle, 1400)! - 1666.6666666666667) < 1e-9);
  assert.equal(sensitivityFromAngle(1000, 0.05, 1400), null);
});

test('evaluateTurn reports degrees and refuses to clamp', async () => {
  const { evaluateTurn, SENS_MAX } = await import('./calibration.ts');
  const ok = evaluateTurn(2048, 0.6);
  assert.equal(ok.ok, true);
  if (ok.ok) {
    assert.equal(ok.sensitivity, Math.round(2048 / 0.6));
    assert.ok(Math.abs(ok.degrees - 34.377) < 0.01);
  }
  // 2560 pt ultrawide from ~1.5 m: ~21 degrees -> above the old 4000 cap, now fine
  const far = evaluateTurn(2048, (21 * Math.PI) / 180);
  assert.equal(far.ok, true);
  const small = evaluateTurn(2048, 2048 / SENS_MAX / 2);
  assert.deepEqual([small.ok, !small.ok && small.reason], [false, 'small']);
  const large = evaluateTurn(2048, 9);
  assert.deepEqual([large.ok, !large.ok && large.reason], [false, 'large']);
  assert.equal(evaluateTurn(2048, Number.NaN).ok, false);
  assert.equal(evaluateTurn(2048, -0.6).ok, true); // direction does not matter
});

test('corner targets are inset 8 %', async () => {
  const { targetFraction, CORNER_SPAN } = await import('./calibration.ts');
  assert.deepEqual(targetFraction('center'), { x: 0.5, y: 0.5 });
  assert.deepEqual(targetFraction('tl'), { x: 0.08, y: 0.08 });
  assert.deepEqual(targetFraction('br'), { x: 0.92, y: 0.92 });
  assert.ok(Math.abs(CORNER_SPAN - 0.84) < 1e-12);
});

test('integrator tracks bias-corrected yaw and pitch from reset', async () => {
  const { AngleIntegrator } = await import('./calibration.ts');
  const it = new AngleIntegrator();
  const bias = { biasX: 0.1, biasZ: -0.1 };
  // 1 s turning right at 0.5 rad/s (z = -0.5 + bias) and tipping up 0.25 rad/s
  for (let i = 0; i <= 60; i++) it.add({ x: 0.25 + 0.1, y: 0, z: -0.5 - 0.1, timestamp: i / 60 }, bias);
  assert.ok(Math.abs(it.yaw - 0.5) < 1e-9, `yaw=${it.yaw}`);
  assert.ok(Math.abs(it.pitch - 0.25) < 1e-9, `pitch=${it.pitch}`);
  it.add({ x: 0, y: 0, z: 5, timestamp: 2 }, bias); // 1 s gap: skipped
  assert.ok(Math.abs(it.yaw - 0.5) < 1e-9);
  it.reset();
  assert.deepEqual(it.snapshot(), { yaw: 0, pitch: 0 });
});

test('evaluateCorners averages both spans per axis', async () => {
  const { evaluateCorners } = await import('./calibration.ts');
  // 1512 x 982 display, 0.4 rad across, 0.3 rad up-down (top corners pitch +0.15)
  const c = {
    tl: { yaw: -0.2, pitch: 0.15 },
    tr: { yaw: 0.2, pitch: 0.15 },
    br: { yaw: 0.22, pitch: -0.15 },
    bl: { yaw: -0.18, pitch: -0.15 },
  };
  const r = evaluateCorners(c, 1512, 982);
  assert.equal(r.ok, true);
  if (r.ok) {
    assert.equal(r.sensitivity, Math.round((0.84 * 1512) / 0.4));
    assert.equal(r.sensitivityY, Math.round((0.84 * 982) / 0.3));
  }
});

test('evaluateCorners asks for a retry per axis instead of clamping', async () => {
  const { evaluateCorners } = await import('./calibration.ts');
  const flatY = { tl: { yaw: -0.2, pitch: 0 }, tr: { yaw: 0.2, pitch: 0 }, br: { yaw: 0.2, pitch: 0.01 }, bl: { yaw: -0.2, pitch: 0.01 } };
  const y = evaluateCorners(flatY, 1512, 982);
  assert.deepEqual([y.ok, !y.ok && y.axis, !y.ok && y.reason], [false, 'y', 'small']);
  const hugeX = { tl: { yaw: -3, pitch: 0.15 }, tr: { yaw: 3, pitch: 0.15 }, br: { yaw: 3, pitch: -0.15 }, bl: { yaw: -3, pitch: -0.15 } };
  const x = evaluateCorners(hugeX, 1512, 982);
  assert.deepEqual([x.ok, !x.ok && x.axis, !x.ok && x.reason], [false, 'x', 'large']);
});

test('scaleSpeed keeps the X:Y ratio and clamps', async () => {
  const { scaleSpeed, SENS_MAX } = await import('./calibration.ts');
  assert.deepEqual(scaleSpeed({ sensitivity: 2000, sensitivityY: 1500 }, 3000), { sensitivity: 3000, sensitivityY: 2250 });
  assert.deepEqual(scaleSpeed({ sensitivity: 1000, sensitivityY: 0 }, 1200), { sensitivity: 1200, sensitivityY: 1200 });
  assert.equal(scaleSpeed({ sensitivity: 1000, sensitivityY: 4000 }, 4000).sensitivityY, SENS_MAX);
});
