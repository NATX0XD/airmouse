/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { calibrationPaused, calibrationShouldClose, PauseLatch } from './pause.ts';

test('pause is idempotent: double pause, single resume resumes', () => {
  const p = new PauseLatch();
  assert.equal(p.set('calibration', true), true);
  assert.equal(p.set('calibration', true), false);
  assert.equal(p.paused, true);
  assert.equal(p.set('calibration', false), true);
  assert.equal(p.paused, false);
  assert.equal(p.set('calibration', false), false);
});

test('clear always resumes', () => {
  const p = new PauseLatch();
  p.set('calibration', true);
  assert.equal(p.clear(), true);
  assert.equal(p.paused, false);
  assert.equal(p.clear(), false);
});

test('calibration pause follows what is on screen', () => {
  assert.equal(calibrationPaused({ calibOpen: true, preview: false, appActive: true }), true);
  // every exit path: closed (done / cancel / Mac cancel / disconnect), preview, background
  assert.equal(calibrationPaused({ calibOpen: false, preview: false, appActive: true }), false);
  assert.equal(calibrationPaused({ calibOpen: true, preview: true, appActive: true }), false);
  assert.equal(calibrationPaused({ calibOpen: true, preview: false, appActive: false }), false);
});

test('calibration closes on background and on losing the Mac it started with', () => {
  const base = { calibOpen: true, appState: 'active', startedConnected: true, connected: true };
  assert.equal(calibrationShouldClose(base), false);
  assert.equal(calibrationShouldClose({ ...base, appState: 'background' }), true);
  assert.equal(calibrationShouldClose({ ...base, appState: 'inactive' }), false); // proximity screen-off, Control Center
  assert.equal(calibrationShouldClose({ ...base, connected: false }), true);
  assert.equal(calibrationShouldClose({ ...base, startedConnected: false, connected: false }), false); // offline calibration
  assert.equal(calibrationShouldClose({ ...base, calibOpen: false, appState: 'background' }), false);
});

test('a session that opens, finishes and closes leaves pointing on', () => {
  const p = new PauseLatch();
  const sync = (calibOpen: boolean) => p.set('calibration', calibrationPaused({ calibOpen, preview: false, appActive: true }));
  sync(true);
  sync(true); // re-render / remount with a new key
  assert.equal(p.paused, true);
  sync(false); // Done, Close, auto-close, Mac cancel, disconnect
  assert.equal(p.paused, false);
});
