/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { eraseAll, KNOWN_KEYS, SETTINGS_KEY } from './reset.ts';
import { FLAG_KEYS, launchStep } from './onboarding.ts';

function memory(initial: Record<string, string>, failKeys = false) {
  const data = new Map(Object.entries(initial));
  return {
    data,
    getAllKeys: async () => {
      if (failKeys) throw new Error('nope');
      return [...data.keys()];
    },
    multiRemove: async (keys: string[]) => {
      keys.forEach((k) => data.delete(k));
    },
  };
}

test('reset erases every stored key, known or not', async () => {
  const s = memory({ [SETTINGS_KEY]: '{"calibratedV3":["x"]}', [FLAG_KEYS.welcome]: '1', [FLAG_KEYS.setup]: '1', [FLAG_KEYS.tour]: '1', 'other.lib': 'y' });
  await eraseAll(s);
  assert.equal(s.data.size, 0);
});

test('known keys go even when listing keys fails', async () => {
  const s = memory({ [SETTINGS_KEY]: '{}', [FLAG_KEYS.tour]: '1' }, true);
  await eraseAll(s);
  assert.equal(s.data.size, 0);
});

test('known keys cover settings and every onboarding flag', () => {
  for (const k of [SETTINGS_KEY, ...Object.values(FLAG_KEYS)]) assert.ok(KNOWN_KEYS.includes(k), k);
});

test('after a reset the app starts with Welcome', () => {
  assert.equal(launchStep({ welcome: false, setup: false, tour: false }, false), 'welcome');
});
