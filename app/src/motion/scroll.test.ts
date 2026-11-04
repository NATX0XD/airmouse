/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { ScrollCoalescer, VelocityTracker, fingerToScroll, momentumSteps, NOTCH_PT, SCROLL_STEP_PX } from './scroll.ts';

test('finger travel maps to fractional points with direction and speed', () => {
  assert.ok(Math.abs(fingerToScroll(SCROLL_STEP_PX, true, 1) - NOTCH_PT) < 1e-9); // 14 px finger = 1 notch = 12 pt
  assert.ok(Math.abs(fingerToScroll(SCROLL_STEP_PX, false, 1) + NOTCH_PT) < 1e-9);
  assert.ok(Math.abs(fingerToScroll(7, true, 2) - 12) < 1e-9);
  assert.ok(Math.abs(fingerToScroll(3, true, 1) - (3 * 12) / 14) < 1e-12);
});

test('coalescer sums a frame and keeps crumbs', () => {
  const c = new ScrollCoalescer();
  c.add(0.3);
  c.add(0.25);
  assert.equal(c.take(), 0.55);
  assert.equal(c.take(), null);
  c.add(0.003);
  assert.equal(c.take(), null); // too small, kept
  c.add(0.004);
  assert.equal(c.take(), 0.01);
  c.add(0.002);
  assert.equal(c.drain(), 0);
});

test('velocity is per frame and zero after the finger stopped', () => {
  const v = new VelocityTracker();
  for (let t = 0; t <= 64; t += 16) v.add(1, t); // 1 notch per frame
  assert.ok(Math.abs(v.perFrame(64) - 1) < 0.05, `v=${v.perFrame(64)}`);
  assert.equal(v.perFrame(300), 0); // held still before release
});

test('momentum decays by 0.95 per frame until under 0.5', () => {
  const s = momentumSteps(2);
  assert.equal(s[0], 2);
  assert.equal(s[1], 1.9);
  assert.ok(s.every((x) => x >= 0.5));
  assert.equal(s.length, Math.ceil(Math.log(0.5 / 2) / Math.log(0.95)));
  assert.deepEqual(momentumSteps(0.4), []);
  assert.equal(momentumSteps(-1000)[0], -150); // capped
});
