/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { isUpright, PlacementDetector, placementHint } from './placement.ts';

const g = (t: number, z = 0.01) => ({ x: 0.01, y: -0.01, z, timestamp: t });
const UPRIGHT = { x: 0.02, y: -0.98, z: 0.1 }; // screen facing the display, portrait
const FLAT = { x: 0.0, y: -0.05, z: -1.0 }; // lying on the desk

test('upright needs gravity along Y and little along Z', () => {
  assert.equal(isUpright(UPRIGHT), true);
  assert.equal(isUpright({ x: 0, y: 0.9, z: 0.2 }), true); // upside down still counts
  assert.equal(isUpright(FLAT), false);
  assert.equal(isUpright({ x: 0, y: -0.7, z: 0.7 }), false); // leaning back 45 degrees
  assert.equal(isUpright(null), false);
});

test('still on the desk never completes (the old false positive)', () => {
  const d = new PlacementDetector();
  for (let i = 0; i <= 60; i++) {
    const r = d.update(g(i * 0.05), { near: false, accel: FLAT });
    assert.equal(r.done, false);
    assert.equal(r.progress, 0);
    assert.equal(r.still, false);
  }
});

test('near + upright + still for 2 s completes', () => {
  const d = new PlacementDetector({ holdSeconds: 2 });
  let last = d.update(g(0), { near: true, accel: UPRIGHT });
  assert.equal(placementHint(last), 'holding');
  for (let i = 1; i <= 40; i++) last = d.update(g(i * 0.05), { near: true, accel: UPRIGHT });
  assert.equal(last.done, true);
  assert.equal(placementHint(last), 'done');
  assert.ok(d.stillSamples().length > 30);
});

test('any condition failing resets progress', () => {
  const d = new PlacementDetector({ holdSeconds: 2 });
  d.update(g(0), { near: true, accel: UPRIGHT });
  assert.ok(d.update(g(1.5), { near: true, accel: UPRIGHT }).progress > 0.7);
  const off = d.update(g(1.55), { near: false, accel: UPRIGHT });
  assert.deepEqual([off.progress, off.still, off.near, placementHint(off)], [0, false, false, 'bring']);
  d.update(g(1.6), { near: true, accel: UPRIGHT });
  const tilted = d.update(g(1.7), { near: true, accel: FLAT });
  assert.equal(placementHint(tilted), 'upright');
  d.update(g(1.8), { near: true, accel: UPRIGHT });
  const moved = d.update(g(1.9, 0.6), { near: true, accel: UPRIGHT });
  assert.equal(placementHint(moved), 'still');
  assert.equal(moved.progress, 0);
});

test('lifting after success keeps it done (auto-advance waits for near = false)', () => {
  const d = new PlacementDetector({ holdSeconds: 1 });
  d.update(g(0), { near: true, accel: UPRIGHT });
  assert.equal(d.update(g(1), { near: true, accel: UPRIGHT }).done, true);
  const lifted = d.update(g(1.1, 2), { near: false, accel: FLAT });
  assert.equal(lifted.done, true);
  assert.equal(lifted.near, false);
  d.reset();
  assert.equal(d.update(g(2), { near: true, accel: UPRIGHT }).done, false);
});
