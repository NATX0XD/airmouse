import type { Msg } from './types';

export type MouseReport = Uint8Array;

const LIMIT = 127;
const keyCode = { left: 1, right: 2 } as const;

function signedByte(value: number): number {
  return value < 0 ? value + 256 : value;
}

function take(value: number): number {
  return Math.sign(value) * Math.min(LIMIT, Math.abs(Math.trunc(value)));
}

// Shared wire format: buttons, dx, dy, wheel, key. Negative int8 values are
// represented as two's-complement bytes. Msg scroll is content movement
// (positive means down), while HID wheel is positive for scrolling up, so the
// encoder deliberately sends wheel = -scroll.dy.
export class ReportEncoder {
  private buttons = 0;
  // Moves arrive as fractional points; HID reports need integers. Keep the
  // sub-pixel remainder here so slow motion still adds up.
  private remX = 0;
  private remY = 0;
  private readonly screenW: number;
  private readonly screenH: number;
  constructor(screenW = 1920, screenH = 1080) { this.screenW = screenW; this.screenH = screenH; }

  encode(msg: Msg): MouseReport[] {
    switch (msg.t) {
      case 'move': {
        this.remX += msg.dx;
        this.remY += msg.dy;
        const dx = Math.trunc(this.remX);
        const dy = Math.trunc(this.remY);
        this.remX -= dx;
        this.remY -= dy;
        if (dx === 0 && dy === 0) return [];
        return this.split(dx, dy, 0, 0);
      }
      case 'scroll':
        return this.split(0, 0, -msg.dy, 0);
      case 'button': {
        const bit = msg.b === 'left' ? 1 : 2;
        this.buttons = msg.down ? this.buttons | bit : this.buttons & ~bit;
        return [this.report(0, 0, 0, 0)];
      }
      case 'key':
        if (msg.k !== 'left' && msg.k !== 'right') return []; // the 5-byte report only knows slide keys
        return [this.report(0, 0, 0, keyCode[msg.k]), this.report(0, 0, 0, 0)];
      case 'center':
        return [...this.split(-this.screenW * 2, -this.screenH * 2, 0, 0), ...this.split(Math.round(this.screenW / 2), Math.round(this.screenH / 2), 0, 0)];
      default:
        return []; // calib, text and practice have no mouse-report form
    }
  }

  private split(dx: number, dy: number, wheel: number, key: number): MouseReport[] {
    const reports: MouseReport[] = [];
    let x = Math.trunc(dx);
    let y = Math.trunc(dy);
    let w = Math.trunc(wheel);
    do {
      const sx = take(x);
      const sy = take(y);
      const sw = take(w);
      reports.push(this.report(sx, sy, sw, key));
      x -= sx;
      y -= sy;
      w -= sw;
    } while (x !== 0 || y !== 0 || w !== 0);
    return reports;
  }

  private report(dx: number, dy: number, wheel: number, key: number): MouseReport {
    return Uint8Array.of(this.buttons, signedByte(dx), signedByte(dy), signedByte(wheel), key);
  }
}
