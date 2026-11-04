/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { afterStage, calloutPlacement, launchStep, pagerBack, pagerNext, shouldStartTour, TOUR, tourNext, tourSkip, tourStart, WELCOME_PAGES } from './onboarding.ts';

const none = { welcome: false, setup: false, tour: false };

test('first launch: welcome, then setup, then connect', () => {
  assert.equal(launchStep(none, false), 'welcome');
  assert.equal(afterStage('welcome', none, false), 'setup');
  assert.equal(afterStage('setup', { ...none, welcome: true }, false), 'connect');
  assert.equal(launchStep({ welcome: true, setup: true, tour: false }, true), 'app');
});

test('welcome pager walks three pages then finishes', () => {
  let p = { index: 0, done: false };
  p = pagerNext(p, WELCOME_PAGES.length);
  p = pagerNext(p, WELCOME_PAGES.length);
  assert.deepEqual(p, { index: 2, done: false });
  assert.deepEqual(pagerNext(p, WELCOME_PAGES.length), { index: 2, done: true });
  assert.deepEqual(pagerBack({ index: 0, done: false }), { index: 0, done: false });
});

test('tour covers the spec targets in order and ends after the last', () => {
  assert.deepEqual(TOUR.map((s) => s.target), ['pill', 'pad', 'scroll', 'clicks', 'center', 'calibrate', 'settingsTab']);
  let t = tourStart();
  for (let i = 1; i < TOUR.length; i++) t = tourNext(t);
  assert.deepEqual(t, { index: TOUR.length - 1, active: true });
  assert.deepEqual(tourNext(t), { index: 0, active: false });
  assert.equal(tourSkip().active, false);
});

test('tour starts only once, connected, on Remote, with no sheet open', () => {
  const base = { tourDone: false, connected: true, onRemote: true, modalOpen: false, active: false };
  assert.equal(shouldStartTour(base), true);
  assert.equal(shouldStartTour({ ...base, tourDone: true }), false);
  assert.equal(shouldStartTour({ ...base, connected: false }), false);
  assert.equal(shouldStartTour({ ...base, modalOpen: true }), false);
  assert.equal(shouldStartTour({ ...base, onRemote: false }), false);
});

test('callout goes below when it fits, above otherwise', () => {
  assert.deepEqual(calloutPlacement({ x: 0, y: 60, w: 200, h: 40 }, 852, 150), { top: 114, below: true });
  assert.deepEqual(calloutPlacement({ x: 0, y: 760, w: 300, h: 62 }, 852, 150), { top: 596, below: false });
});
