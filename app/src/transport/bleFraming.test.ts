/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { base64ToBytes, bytesToBase64, frame, Outbox, unframe, utf8Decode, utf8Encode } from './bleFraming.ts';
import { decodeInbound, helloMessage } from './protocol.ts';

test('base64 matches Node for every padding length', () => {
  for (const text of ['', 'a', 'ab', 'abc', 'abcd', '{"t":"move","dx":-3,"dy":12}']) {
    const bytes = utf8Encode(text);
    assert.equal(bytesToBase64(bytes), Buffer.from(text, 'utf8').toString('base64'));
    assert.deepEqual([...base64ToBytes(bytesToBase64(bytes))], [...bytes]);
  }
});

test('UTF-8 round-trips non-ASCII Mac names', () => {
  const name = 'Nattakit’s MacBook Pro ณัฐกิตติ์ 🖱️';
  assert.deepEqual([...utf8Encode(name)], [...Buffer.from(name, 'utf8')]);
  assert.equal(utf8Decode(Buffer.from(name, 'utf8')), name);
  assert.equal(utf8Decode(Uint8Array.of(0x41, 0xe2, 0x41)), 'A�A');
});

test('frame -> unframe -> decode a screen notification', () => {
  const b64 = Buffer.from('{"t":"screen","w":1512,"h":982,"name":"Studio Display"}', 'utf8').toString('base64');
  assert.deepEqual(decodeInbound(unframe(b64)), { t: 'screen', w: 1512, h: 982, name: 'Studio Display' });
  assert.equal(Buffer.from(frame({ t: 'center' }), 'base64').toString('utf8'), '{"t":"center"}');
});

test('typical messages fit in one small write', () => {
  const size = (b64: string) => base64ToBytes(b64).length;
  assert.ok(size(frame({ t: 'move', dx: -1234, dy: 987 })) < 60);
  assert.ok(size(frame({ t: 'button', b: 'right', down: false })) < 60);
  assert.ok(size(frame({ t: 'calib', step: 'place', progress: 0.875, still: true })) < 60);
  // hello is sent with response, so iOS long-writes it if it beats the MTU
  assert.ok(size(frame(helloMessage({ name: 'iPhone', model: 'iPhone 15 Pro Max', wMm: 76.7, hMm: 159.9 }))) < 182);
});

test('outbox merges consecutive moves and keeps order around clicks', () => {
  const box = new Outbox();
  box.push({ t: 'move', dx: 1, dy: 2 });
  box.push({ t: 'move', dx: 3, dy: -1 });
  box.push({ t: 'button', b: 'left', down: true });
  box.push({ t: 'move', dx: 5, dy: 0 });
  assert.equal(box.size, 3);
  assert.deepEqual(box.shift(), { t: 'move', dx: 4, dy: 1 });
  assert.deepEqual(box.shift(), { t: 'button', b: 'left', down: true });
  assert.deepEqual(box.shift(), { t: 'move', dx: 5, dy: 0 });
  assert.equal(box.shift(), undefined);
});
