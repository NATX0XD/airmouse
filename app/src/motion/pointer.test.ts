/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { isTap, pointerActive } from './pointer.ts';
import { MotionEngine, type GyroSample } from './engine.ts';

test('Always On points with no touch; a touch pauses it', () => {
  assert.equal(pointerActive('always', false), true);
  assert.equal(pointerActive('always', true), false);
});

test('Hold to Point points only while touching', () => {
  assert.equal(pointerActive('hold', false), false);
  assert.equal(pointerActive('hold', true), true);
});

test('Always On with no touch actually produces moves', () => {
  const engine = new MotionEngine();
  let dx = 0;
  for (let i = 0; i <= 30; i++) {
    const s: GyroSample = { x: 0, y: 0, z: -1, timestamp: i / 60 };
    dx += engine.update(s, pointerActive('always', false)).dx;
  }
  assert.ok(dx > 0, `dx=${dx}`);
});

test('a quick touch is a tap (left click), a long hold is not', () => {
  assert.equal(isTap(1000, 1120), true);
  assert.equal(isTap(1000, 1250), false);
});
