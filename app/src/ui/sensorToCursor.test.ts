/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { burstPos, dotsMoved, EXAMPLE_DEG_PER_SEC, EXAMPLE_DOTS_PER_DEG, rawLine, smoothLine, wobble } from './sensorToCursor.ts';

test('worked example: 29 deg/s for 10 ms is about 7 dots, about 700 in a second', () => {
  assert.equal(Math.round(dotsMoved(EXAMPLE_DEG_PER_SEC, 10, EXAMPLE_DOTS_PER_DEG)), 7);
  assert.equal(Math.round(dotsMoved(EXAMPLE_DEG_PER_SEC, 1000, EXAMPLE_DOTS_PER_DEG) / 100) * 100, 700);
});

test('wobble stays within -1..1 and is deterministic', () => {
  for (let i = 0; i < 200; i++) assert.ok(Math.abs(wobble(i * 0.37)) <= 1);
  assert.equal(wobble(3.2), wobble(3.2));
});

test('smooth line deviates far less than raw line', () => {
  let raw = 0; let smooth = 0;
  for (let i = 0; i <= 100; i++) { const u = i / 100; raw += Math.abs(rawLine(u, 0.1) - smoothLine(u, 0)); smooth += Math.abs(smoothLine(u, 0.1) - smoothLine(u, 0)); }
  assert.ok(smooth < raw / 5);
});

test('burstPos stays in 0..1', () => {
  for (let i = 0; i < 12; i++) for (const ph of [0, 0.3, 0.99]) { const p = burstPos(i, ph); assert.ok(p >= 0 && p < 1); }
});
