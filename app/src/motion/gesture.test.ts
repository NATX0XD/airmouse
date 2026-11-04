import assert from 'node:assert/strict';
import test from 'node:test';
import { FlickDetector } from './gesture.ts';

const s = (z: number, t: number) => ({ x: 0, y: 0, z, timestamp: t });

test('yaw flick maps sensor z to slide direction', () => {
  const d = new FlickDetector();
  assert.equal(d.update(s(-4.5, 1)), null);
  assert.equal(d.update(s(-1, 1.1)), 'right');
  assert.equal(d.update(s(5, 1.2)), null);
  assert.equal(d.update(s(5, 1.8)), null);
  assert.equal(d.update(s(0, 1.9)), 'left');
});

test('slow or weak movement does not trigger', () => {
  const d = new FlickDetector();
  assert.equal(d.update(s(3.9, 1)), null);
  assert.equal(d.update(s(-4, 1.3)), null);
  assert.equal(d.update(s(0, 1.4)), 'right');
});

test('long strong turn does not trigger', () => {
  const d = new FlickDetector({ maxDurationMs: 220 });
  assert.equal(d.update(s(5, 1)), null);
  assert.equal(d.update(s(5, 1.5)), null);
  assert.equal(d.update(s(0, 1.6)), null);
});
