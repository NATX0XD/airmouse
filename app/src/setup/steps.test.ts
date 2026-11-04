/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { actionsFor, back, INITIAL_STATUSES, missing, next, startAt, STEPS } from './steps.ts';

const step = (id: string) => STEPS.find((s) => s.id === id)!;

test('order: Local Network, Bluetooth, Camera, Motion', () => {
  assert.deepEqual(STEPS.map((s) => s.id), ['localNetwork', 'bluetooth', 'camera', 'motion']);
});

test('required Local Network cannot be skipped until denied', () => {
  assert.deepEqual(actionsFor(step('localNetwork'), 'unknown'), { primary: 'request', canSkip: false });
  assert.deepEqual(actionsFor(step('localNetwork'), 'denied'), { primary: 'openSettings', canSkip: true });
  assert.deepEqual(actionsFor(step('localNetwork'), 'granted'), { primary: 'continue', canSkip: false });
});

test('optional steps can be skipped; motion is automatic', () => {
  assert.deepEqual(actionsFor(step('camera'), 'unknown'), { primary: 'request', canSkip: true });
  assert.deepEqual(actionsFor(step('motion'), 'unknown'), { primary: 'wait', canSkip: true });
  assert.deepEqual(actionsFor(step('motion'), 'unavailable'), { primary: 'continue', canSkip: false });
});

test('next walks through steps and finishes after the last', () => {
  let s = { index: 0, done: false };
  s = next(s);
  s = next(s);
  s = next(s);
  assert.deepEqual(s, { index: 3, done: false });
  assert.deepEqual(next(s), { index: 3, done: true });
  assert.deepEqual(back({ index: 0, done: false }), { index: 0, done: false });
  assert.deepEqual(back({ index: 2, done: false }), { index: 1, done: false });
});

test('warning rows reopen the right step', () => {
  assert.deepEqual(missing(INITIAL_STATUSES), []);
  assert.deepEqual(missing({ ...INITIAL_STATUSES, localNetwork: 'denied', camera: 'denied' }), ['localNetwork', 'camera']);
  assert.deepEqual(startAt('camera'), { index: 2, done: false });
});
