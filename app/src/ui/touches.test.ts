/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { TouchSet } from './touches.ts';

test('pad and button track their own fingers', () => {
  const pad = new TouchSet();
  const left = new TouchSet();
  assert.equal(pad.down(1), true); // finger 1 holds the pad
  assert.equal(left.down(2), true); // finger 2 presses Left
  // Finger 2 lifts: the event may list it on both views.
  assert.equal(left.up([{ identifier: 2 }]), true);
  assert.equal(pad.up([{ identifier: 2 }]), false);
  assert.equal(pad.active, true);
  assert.equal(pad.up([{ identifier: 1 }]), true);
});

test('a second finger on the same view keeps it pressed until both lift', () => {
  const s = new TouchSet();
  assert.equal(s.down(1), true);
  assert.equal(s.down(2), false);
  assert.equal(s.up([{ identifier: 1 }]), false);
  assert.equal(s.up([{ identifier: 2 }]), true);
  assert.equal(s.up([{ identifier: 2 }]), false); // duplicate end is a no-op
});

test('sync releases fingers no longer on screen', () => {
  const s = new TouchSet();
  s.down(5);
  assert.equal(s.sync([{ identifier: 5 }, { identifier: 6 }]), false);
  assert.equal(s.sync([{ identifier: 6 }]), true);
  assert.equal(s.active, false);
});

test('clear reports whether anything was held', () => {
  const s = new TouchSet();
  assert.equal(s.clear(), false);
  s.down('a');
  assert.equal(s.clear(), true);
});
