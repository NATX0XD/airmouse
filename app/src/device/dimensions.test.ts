/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { bodySizeFor, FALLBACK_SIZE } from './dimensions.ts';

test('looks up iPhone 15 by model id', () => {
  assert.deepEqual(bodySizeFor('iPhone15,4'), { wMm: 71.6, hMm: 147.6 });
});

test('falls back to the marketing name, case-insensitive', () => {
  assert.deepEqual(bodySizeFor(null, 'iPhone 17 Pro'), { wMm: 71.9, hMm: 150.0 });
  assert.deepEqual(bodySizeFor('arm64', ' iphone air '), { wMm: 74.7, hMm: 156.2 });
});

test('unknown models get the generic size', () => {
  assert.deepEqual(bodySizeFor('iPhone99,1', 'iPhone 99'), FALLBACK_SIZE);
  assert.deepEqual(bodySizeFor(undefined), { wMm: 71.5, hMm: 147.5 });
});
