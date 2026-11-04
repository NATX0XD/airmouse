/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { markCalibrated, migrateMotion, readCalibrated, screenKey, shouldPromptCalibration } from './calibrated.ts';

const mac = { w: 1512, h: 982, name: 'Built-in Retina Display' };
const base = { connected: true, screen: mac, calibrated: [] as string[], dismissed: false, busy: false };

test('old motion settings get sensitivityY = sensitivity and default acceleration', () => {
  const m = migrateMotion({ sensitivity: 2100, deadzone: 0.02 } as never);
  assert.equal(m.sensitivityY, 2100);
  assert.equal(m.acceleration, 0.4);
  assert.equal(migrateMotion({ sensitivity: 2100, sensitivityY: 1800, acceleration: 0 } as never).sensitivityY, 1800);
  assert.equal(migrateMotion({ acceleration: 7 } as never).acceleration, 1);
  assert.equal(migrateMotion(undefined).sensitivityY, migrateMotion(undefined).sensitivity);
});

test('prompt shows once per uncalibrated Mac, not after Later', () => {
  assert.equal(shouldPromptCalibration(base), true);
  assert.equal(shouldPromptCalibration({ ...base, dismissed: true }), false);
  assert.equal(shouldPromptCalibration({ ...base, connected: false }), false);
  assert.equal(shouldPromptCalibration({ ...base, screen: null }), false);
  assert.equal(shouldPromptCalibration({ ...base, busy: true }), false);
  assert.equal(shouldPromptCalibration({ ...base, calibrated: markCalibrated([], mac) }), false);
  // a different display on the same Mac name still asks
  assert.equal(shouldPromptCalibration({ ...base, screen: { ...mac, w: 2560, h: 1440 }, calibrated: markCalibrated([], mac) }), true);
});

test('only v3 calibrations count: legacy results start uncalibrated', () => {
  assert.deepEqual(readCalibrated(undefined), []); // old 2-dot calibratedAt alone = not calibrated
  assert.deepEqual(readCalibrated(['a', 3]), ['a']);
  assert.deepEqual(readCalibrated('x'), []);
  assert.deepEqual(markCalibrated([screenKey(mac)], mac), [screenKey(mac)]);
});
