/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { shouldEmit, StillnessDetector } from './stillness.ts';

const s = (z: number, t: number) => ({ x: 0.01, y: -0.01, z, timestamp: t });

test('progress grows while still and completes after 2 s', () => {
  const d = new StillnessDetector();
  assert.deepEqual(d.update(s(0, 0)), { progress: 0, still: true, done: false });
  const mid = d.update(s(0.02, 1));
  assert.equal(mid.progress, 0.5);
  assert.equal(mid.done, false);
  const end = d.update(s(0.02, 2));
  assert.equal(end.done, true);
  assert.equal(end.progress, 1);
  assert.equal(d.stillSamples().length, 3);
});

test('movement drains progress to zero and restarts the clock', () => {
  const d = new StillnessDetector();
  d.update(s(0, 0));
  d.update(s(0, 1.5));
  assert.deepEqual(d.update(s(0.5, 1.6)), { progress: 0, still: false, done: false });
  assert.equal(d.stillSamples().length, 0);
  d.update(s(0, 1.7));
  assert.ok(Math.abs(d.update(s(0, 2.7)).progress - 0.5) < 1e-9);
});

test('done is sticky until reset', () => {
  const d = new StillnessDetector({ holdSeconds: 1 });
  d.update(s(0, 0));
  d.update(s(0, 1));
  assert.equal(d.update(s(3, 1.1)).done, true);
  d.reset();
  assert.equal(d.update(s(0, 2)).done, false);
});

test('NaN readings count as movement', () => {
  assert.equal(new StillnessDetector().update(s(Number.NaN, 0)).still, false);
});

test('rate limiter lets through ~10 Hz', () => {
  assert.equal(shouldEmit(0, null, 100), true);
  assert.equal(shouldEmit(50, 0, 100), false);
  assert.equal(shouldEmit(100, 0, 100), true);
});
