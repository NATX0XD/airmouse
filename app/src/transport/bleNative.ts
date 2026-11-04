import { AirMouseBle, type NativeBleStats } from '../../modules/airmouse-discovery';
import type { BluetoothMac } from './bleMac';
import { decodeInbound, encode, helloMessage } from './protocol';
import type { DeviceInfo, InboundMsg, Msg, Transport, TransportStatus } from './types';

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export const nativeBleAvailable = (): boolean => !!AirMouseBle;

// Bluetooth to the Mac through the native central (modules/airmouse-discovery
// AirMouseBleModule.swift): write without response, moves summed natively,
// no JS round trip per write. Reconnects by itself until close().
export class NativeBleMacTransport implements Transport {
  readonly label: string;
  onIdChange?: (mac: BluetoothMac) => void;
  private id: string;
  private readonly name: string;
  private readonly info: DeviceInfo;
  private wanted = false;
  private isOpen = false;
  private retry: ReturnType<typeof setTimeout> | null = null;
  private subs: { remove(): void }[] = [];
  private listeners = new Set<(s: TransportStatus, detail?: string) => void>();
  private messageListeners = new Set<(m: InboundMsg) => void>();
  private benchWaiter: ((r: Record<string, unknown>) => void) | null = null;
  private lastBench = '';
  private rate = { at: 0, writes: 0, moves: 0, writeHz: 0, moveHz: 0 };

  constructor(mac: BluetoothMac, info: DeviceInfo) {
    this.id = mac.id;
    this.name = mac.name;
    this.label = mac.name;
    this.info = info;
  }

  onStatus(cb: (s: TransportStatus, detail?: string) => void) {
    this.listeners.add(cb);
    return () => this.listeners.delete(cb);
  }

  onMessage(cb: (m: InboundMsg) => void) {
    this.messageListeners.add(cb);
    return () => this.messageListeners.delete(cb);
  }

  private emit(s: TransportStatus, detail?: string) {
    this.listeners.forEach((cb) => cb(s, detail));
  }

  connect() {
    const ble = AirMouseBle;
    if (!ble) return this.emit('error', 'Bluetooth isn’t available in this build.');
    this.wanted = true;
    if (this.subs.length === 0) {
      this.subs.push(
        ble.addListener('onBleStatus', (e) => {
          if (!this.wanted) return;
          if (e.status === 'open') {
            this.isOpen = true;
            if (e.id && e.id !== this.id) {
              this.id = e.id;
              this.onIdChange?.({ id: e.id, name: this.name });
            }
            ble.send(encode(helloMessage(this.info)));
            this.emit('open');
          } else if (e.status === 'connecting') {
            this.emit('connecting');
          } else {
            this.isOpen = false;
            this.emit(e.status === 'error' ? 'error' : 'connecting', e.detail ?? `Can’t reach ${this.name} over Bluetooth. Keep AirMouse open on the Mac.`);
            this.scheduleRetry(e.status === 'error' ? 2500 : 1000);
          }
        }),
        ble.addListener('onBleMessage', (e) => {
          if (e.text.startsWith('{"t":"benchResult"')) {
            try {
              const r = JSON.parse(e.text) as Record<string, unknown>;
              if (r.step !== 'started') this.benchWaiter?.(r);
            } catch {
              // ignored
            }
            return;
          }
          const m = decodeInbound(e.text);
          if (m) this.messageListeners.forEach((cb) => cb(m));
        }),
      );
    }
    ble.connect(this.id, this.name);
  }

  private scheduleRetry(ms: number) {
    if (!this.wanted || this.retry) return;
    this.retry = setTimeout(() => {
      this.retry = null;
      if (this.wanted) AirMouseBle?.connect(this.id, this.name);
    }, ms);
  }

  close() {
    this.wanted = false;
    this.isOpen = false;
    if (this.retry) clearTimeout(this.retry);
    this.retry = null;
    this.subs.forEach((s) => s.remove());
    this.subs = [];
    AirMouseBle?.disconnect();
    this.emit('idle');
  }

  send(msg: Msg): boolean {
    const ble = AirMouseBle;
    if (!ble || !this.isOpen) return false;
    if (msg.t === 'move') ble.sendMove(msg.dx, msg.dy);
    else ble.send(encode(msg));
    return true;
  }

  private stats(): NativeBleStats | null {
    try {
      return AirMouseBle?.stats() ?? null;
    } catch {
      return null;
    }
  }

  debugStats(): Record<string, string | number> {
    const s = this.stats();
    if (!s) return { link: 'native module missing' };
    // Rates from successive samples (Diagnostics polls a few times a second).
    const now = Date.now();
    const r = this.rate;
    if (r.at && now - r.at >= 500) {
      const dt = (now - r.at) / 1000;
      r.writeHz = Math.round((s.writes - r.writes) / dt);
      r.moveHz = Math.round((s.moves - r.moves) / dt);
    }
    if (!r.at || now - r.at >= 500) Object.assign(r, { at: now, writes: s.writes, moves: s.moves });
    return {
      link: s.open ? 'connected (native)' : 'down',
      'write rate': `${r.writeHz} Hz`,
      'move rate': `${r.moveHz} Hz`,
      bench: this.lastBench,
      queued: s.queued,
      written: s.writes,
      merged: s.merged,
      'waited (buffer full)': s.waits,
      'max write': s.maxWrite,
      'last error': s.lastError,
    };
  }

  // 60 Hz synthetic zero moves for `seconds`; the Mac counts what arrives and
  // answers {t:'benchResult', hz}. Shown in Diagnostics.
  async bench(opts: { seconds?: number } = {}): Promise<string> {
    const ble = AirMouseBle;
    const seconds = opts.seconds ?? 5;
    for (let i = 0; i < 75 && !this.isOpen; i++) await sleep(200);
    if (!ble || !this.isOpen) return (this.lastBench = 'no Bluetooth link');
    this.lastBench = 'running…';
    const s0 = this.stats();
    ble.send(JSON.stringify({ t: 'bench', step: 'start' }));
    const tick = setInterval(() => ble.sendMove(0, 0), 1000 / 60);
    await sleep(seconds * 1000);
    clearInterval(tick);
    const result = new Promise<Record<string, unknown> | null>((resolve) => {
      const timer = setTimeout(() => resolve(null), 2000);
      this.benchWaiter = (r) => {
        clearTimeout(timer);
        resolve(r);
      };
    });
    ble.send(JSON.stringify({ t: 'bench', step: 'end' }));
    const mac = await result;
    this.benchWaiter = null;
    const s1 = this.stats();
    const sent = s0 && s1 ? Math.round(((s1.moves - s0.moves) / seconds) * 10) / 10 : 0;
    const waits = s0 && s1 ? s1.waits - s0.waits : 0;
    this.lastBench = `phone ${sent} Hz · Mac received ${mac ? `${mac.hz} Hz` : '?'} · ${waits} waits`;
    return this.lastBench;
  }
}
