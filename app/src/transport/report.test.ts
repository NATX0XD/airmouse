import assert from 'node:assert/strict';
import test from 'node:test';
import { ReportEncoder } from './report.ts';

const rows = (xs: Uint8Array[]) => xs.map((x) => [...x]);

test('button down/up is never lost', () => {
  const e = new ReportEncoder();
  assert.deepEqual(rows([...e.encode({ t: 'button', b: 'left', down: true }), ...e.encode({ t: 'button', b: 'left', down: false })]), [[1, 0, 0, 0, 0], [0, 0, 0, 0, 0]]);
});

test('splits large positive movement', () => {
  assert.deepEqual(rows(new ReportEncoder().encode({ t: 'move', dx: 300, dy: 0 })), [[0, 127, 0, 0, 0], [0, 127, 0, 0, 0], [0, 46, 0, 0, 0]]);
});

test('encodes negative int8 values as two\'s complement', () => {
  assert.deepEqual(rows(new ReportEncoder().encode({ t: 'move', dx: -130, dy: -4 })), [[0, 129, 252, 0, 0], [0, 253, 0, 0, 0]]);
});

test('reverses content scroll sign for HID wheel', () => {
  assert.deepEqual(rows(new ReportEncoder().encode({ t: 'scroll', dy: 3 })), [[0, 0, 0, 253, 0]]);
});

test('key has a release report', () => {
  assert.deepEqual(rows(new ReportEncoder().encode({ t: 'key', k: 'right' })), [[0, 0, 0, 0, 2], [0, 0, 0, 0, 0]]);
});

test('center uses configured screen size and relative reports', () => {
  const reports = new ReportEncoder(100, 50).encode({ t: 'center' });
  assert.deepEqual(rows(reports), [[0, 129, 156, 0, 0], [0, 183, 0, 0, 0], [0, 50, 25, 0, 0]]);
});

test('fractional moves accumulate into integer reports', () => {
  const enc = new ReportEncoder();
  let dx = 0;
  for (let i = 0; i < 10; i++) {
    for (const rep of enc.encode({ t: 'move', dx: 0.35, dy: 0 })) dx += rep[1] > 127 ? rep[1] - 256 : rep[1];
  }
  assert.equal(dx, 3); // 3.5 sent, 0.5 kept
  assert.deepEqual(enc.encode({ t: 'move', dx: 0.2, dy: 0 }), []);
  assert.deepEqual(enc.encode({ t: 'move', dx: -1.5, dy: 0 }), []); // 0.7 - 1.5 = -0.8: still under a point
  const back = enc.encode({ t: 'move', dx: -0.3, dy: 0 }); // -1.1
  assert.equal(back.length, 1);
  assert.equal(back[0][1], 256 - 1);
});

test('fractional scroll accumulates into whole wheel notches', () => {
  const enc = new ReportEncoder();
  assert.deepEqual(enc.encode({ t: 'scroll', dy: 4.8, phase: 'move' }), []); // 0.4 notch
  const r = enc.encode({ t: 'scroll', dy: 8.4, phase: 'move' }); // +0.7 = 1.1 notches
  assert.equal(r.length, 1);
  assert.equal(r[0][3], 255); // wheel -1 (content down)
});
