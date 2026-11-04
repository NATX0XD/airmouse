import type { HelloMsg, Msg } from './types';

// Bluetooth framing for the Mac GATT service: one UTF-8 JSON message per
// characteristic write, base64 on the ble-plx boundary. Pure, no React Native
// (Hermes may lack TextDecoder, so UTF-8 is done by hand).

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

export function utf8Encode(text: string): Uint8Array {
  const out: number[] = [];
  for (const ch of text) {
    let cp = ch.codePointAt(0)!;
    if (cp >= 0xd800 && cp <= 0xdfff) cp = 0xfffd; // lone surrogate
    if (cp < 0x80) out.push(cp);
    else if (cp < 0x800) out.push(0xc0 | (cp >> 6), 0x80 | (cp & 63));
    else if (cp < 0x10000) out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
    else out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
  }
  return Uint8Array.from(out);
}

export function utf8Decode(bytes: Uint8Array): string {
  let s = '';
  let i = 0;
  while (i < bytes.length) {
    const b = bytes[i];
    const need = b < 0x80 ? 0 : b >= 0xf8 ? -1 : b >= 0xf0 ? 3 : b >= 0xe0 ? 2 : b >= 0xc0 ? 1 : -1;
    let ok = need >= 0 && i + need < bytes.length;
    for (let k = 1; ok && k <= need; k++) ok = (bytes[i + k] & 0xc0) === 0x80;
    if (!ok) {
      s += '\uFFFD';
      i += 1;
      continue;
    }
    let cp = need === 0 ? b : b & (0x3f >> need);
    for (let k = 1; k <= need; k++) cp = (cp << 6) | (bytes[i + k] & 63);
    s += String.fromCodePoint(cp);
    i += need + 1;
  }
  return s;
}

export function bytesToBase64(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0);
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63];
    out += i + 1 < bytes.length ? B64[(n >> 6) & 63] : '=';
    out += i + 2 < bytes.length ? B64[n & 63] : '=';
  }
  return out;
}

export function base64ToBytes(b64: string): Uint8Array {
  const clean = b64.replace(/[^A-Za-z0-9+/]/g, '');
  const out: number[] = [];
  for (let i = 0; i < clean.length; i += 4) {
    const v = [0, 1, 2, 3].map((k) => (i + k < clean.length ? B64.indexOf(clean[i + k]) : -1));
    const n = (v[0] << 18) | (v[1] << 12) | (Math.max(0, v[2]) << 6) | Math.max(0, v[3]);
    out.push((n >> 16) & 255);
    if (v[2] >= 0) out.push((n >> 8) & 255);
    if (v[3] >= 0) out.push(n & 255);
  }
  return Uint8Array.from(out);
}

export const frame = (msg: Msg | HelloMsg): string => bytesToBase64(utf8Encode(JSON.stringify(msg)));
export const unframe = (b64: string): string => utf8Decode(base64ToBytes(b64));

// Ordered outbox. Consecutive moves merge into one, so while a write is in
// flight the pointer never queues up a backlog (at most one move per flush).
export class Outbox {
  private items: (Msg | HelloMsg)[] = [];

  push(msg: Msg | HelloMsg): void {
    const last = this.items[this.items.length - 1];
    if (msg.t === 'move' && last?.t === 'move') {
      this.items[this.items.length - 1] = { t: 'move', dx: last.dx + msg.dx, dy: last.dy + msg.dy };
      return;
    }
    this.items.push(msg);
  }

  shift(): Msg | HelloMsg | undefined {
    return this.items.shift();
  }

  get size(): number {
    return this.items.length;
  }

  clear(): void {
    this.items = [];
  }
}
