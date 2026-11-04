/// <reference types="node" />
import assert from 'node:assert/strict';
import test from 'node:test';
import { parseAddress, parseConnectUrl } from './address.ts';

test('parses the Mac QR payload', () => {
  assert.deepEqual(parseConnectUrl('airmouse://connect?host=192.168.1.20&port=8766&name=Nattakit%27s%20MacBook%20Pro'), {
    host: '192.168.1.20', port: 8766, name: "Nattakit's MacBook Pro",
  });
});

test('QR without port uses 8765, plus decodes to space', () => {
  assert.deepEqual(parseConnectUrl('AIRMOUSE://connect/?name=Mac+mini&host=mac.local'), { host: 'mac.local', port: 8765, name: 'Mac mini' });
});

test('rejects foreign or broken QR codes', () => {
  assert.equal(parseConnectUrl('https://example.com/?host=1.2.3.4'), null);
  assert.equal(parseConnectUrl('airmouse://connect?port=8765'), null);
  assert.equal(parseConnectUrl('airmouse://connect?host=1.2.3.4&port=99999'), null);
  assert.equal(parseConnectUrl('airmouse://connect?host=bad%20host'), null);
});

test('parses typed addresses', () => {
  assert.deepEqual(parseAddress(' 192.168.1.20 '), { host: '192.168.1.20', port: 8765 });
  assert.deepEqual(parseAddress('ws://10.0.0.2:9000/'), { host: '10.0.0.2', port: 9000 });
  assert.deepEqual(parseAddress('10.0.0.2', '8800'), { host: '10.0.0.2', port: 8800 });
  assert.equal(parseAddress(''), null);
  assert.equal(parseAddress('10.0.0.2', 'abc'), null);
});
