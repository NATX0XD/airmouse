/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { decodeInbound, encode, helloMessage } from './protocol.ts';
import { ReportEncoder } from './report.ts';

test('hello carries v3 and the device size', () => {
  const hello = helloMessage({ name: 'iPhone', model: 'iPhone 15', wMm: 71.6, hMm: 147.6 });
  assert.deepEqual(JSON.parse(encode(hello)), {
    t: 'hello', v: 3, app: 'airmouse', device: { name: 'iPhone', model: 'iPhone 15', wMm: 71.6, hMm: 147.6 },
  });
});

test('calib messages encode as flat JSON', () => {
  assert.equal(encode({ t: 'calib', step: 'place', progress: 0.5, still: true }), '{"t":"calib","step":"place","progress":0.5,"still":true}');
  assert.equal(encode({ t: 'calib', step: 'pointed', target: 'tl' }), '{"t":"calib","step":"pointed","target":"tl"}');
  assert.equal(encode({ t: 'calib', step: 'point', target: 'center' }), '{"t":"calib","step":"point","target":"center"}');
  assert.equal(encode({ t: 'calib', step: 'verify' }), '{"t":"calib","step":"verify"}');
  assert.equal(encode({ t: 'calib', step: 'done', sensitivity: 1800, sensitivityY: 1500 }), '{"t":"calib","step":"done","sensitivity":1800,"sensitivityY":1500}');
  assert.equal(encode({ t: 'center' }), '{"t":"center"}');
});

test('decodes screen with mm and name, drops unknown fields', () => {
  assert.deepEqual(decodeInbound('{"t":"screen","w":1512,"h":982,"scale":2,"wMm":302,"hMm":196,"name":"Built-in Retina Display","extra":1}'), {
    t: 'screen', w: 1512, h: 982, scale: 2, wMm: 302, hMm: 196, name: 'Built-in Retina Display',
  });
});

test('v2 screen without mm still decodes', () => {
  assert.deepEqual(decodeInbound({ t: 'screen', w: 1920, h: 1080, scale: 1 }), { t: 'screen', w: 1920, h: 1080, scale: 1 });
});

test('rejects invalid screen sizes and half mm pairs', () => {
  assert.equal(decodeInbound('{"t":"screen","w":0,"h":900}'), null);
  assert.equal(decodeInbound('{"t":"screen","w":"1920","h":900}'), null);
  assert.deepEqual(decodeInbound('{"t":"screen","w":10,"h":10,"wMm":300}'), { t: 'screen', w: 10, h: 10 });
});

test('decodes calib request and cancel, ignores other steps', () => {
  assert.deepEqual(decodeInbound('{"t":"calib","step":"request"}'), { t: 'calib', step: 'request' });
  assert.deepEqual(decodeInbound('{"t":"calib","step":"cancel"}'), { t: 'calib', step: 'cancel' });
  assert.equal(decodeInbound('{"t":"calib","step":"place"}'), null);
});

test('unknown types and garbage are ignored', () => {
  assert.equal(decodeInbound('{"t":"party"}'), null);
  assert.equal(decodeInbound('not json'), null);
  assert.equal(decodeInbound('null'), null);
  assert.equal(decodeInbound(42), null);
});

test('HID report encoder skips calib messages', () => {
  assert.deepEqual(new ReportEncoder().encode({ t: 'calib', step: 'start' }), []);
});

test('keyboard and practice messages encode as flat JSON', () => {
  assert.equal(encode({ t: 'text', s: 'Hi é👍' }), '{"t":"text","s":"Hi é👍"}');
  assert.equal(encode({ t: 'key', k: 'backspace' }), '{"t":"key","k":"backspace"}');
  assert.equal(encode({ t: 'key', k: 'escape' }), '{"t":"key","k":"escape"}');
  assert.equal(encode({ t: 'practice', step: 'start' }), '{"t":"practice","step":"start"}');
  assert.equal(encode({ t: 'practice', step: 'stop' }), '{"t":"practice","step":"stop"}');
});

test('decodes focus, rejects non-boolean editable', () => {
  assert.deepEqual(decodeInbound('{"t":"focus","editable":true}'), { t: 'focus', editable: true });
  assert.deepEqual(decodeInbound({ t: 'focus', editable: false, role: 'AXTextField' }), { t: 'focus', editable: false });
  assert.equal(decodeInbound('{"t":"focus","editable":"yes"}'), null);
  assert.equal(decodeInbound('{"t":"focus"}'), null);
});

test('decodes practice running and result, drops bad numbers', () => {
  assert.deepEqual(decodeInbound('{"t":"practice","step":"running"}'), { t: 'practice', step: 'running' });
  assert.deepEqual(decodeInbound('{"t":"practice","step":"result","hits":8,"total":10,"ms":412.5,"x":1}'), {
    t: 'practice', step: 'result', hits: 8, total: 10, ms: 412.5,
  });
  assert.deepEqual(decodeInbound('{"t":"practice","step":"result","hits":-1,"total":"10"}'), { t: 'practice', step: 'result' });
  assert.equal(decodeInbound('{"t":"practice","step":"start"}'), null);
  assert.deepEqual(decodeInbound('{"t":"practice","step":"stop"}'), { t: 'practice', step: 'stop' });
});

test('HID report encoder only maps slide keys', () => {
  const enc = new ReportEncoder();
  assert.equal(enc.encode({ t: 'key', k: 'right' }).length, 2);
  assert.deepEqual(enc.encode({ t: 'key', k: 'enter' }), []);
  assert.deepEqual(enc.encode({ t: 'text', s: 'a' }), []);
  assert.deepEqual(enc.encode({ t: 'practice', step: 'start' }), []);
});

test('decodes calib hit for the 5 targets only', () => {
  for (const target of ['center', 'tl', 'tr', 'br', 'bl']) assert.deepEqual(decodeInbound({ t: 'calib', step: 'hit', target }), { t: 'calib', step: 'hit', target });
  assert.equal(decodeInbound('{"t":"calib","step":"hit","target":"left"}'), null);
  assert.equal(decodeInbound('{"t":"calib","step":"hit"}'), null);
});
