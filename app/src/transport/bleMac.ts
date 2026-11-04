import type { Device, Subscription } from 'react-native-ble-plx';
import { getBleManager } from './bleManager';
import { MAC_NAME_PREFIX, MAC_RX_UUID, MAC_SERVICE_UUID, MAC_TX_UUID } from './bleIds';
import { frame, moveWait, Outbox, unframe } from './bleFraming';
import { decodeInbound, helloMessage } from './protocol';
import type { DeviceInfo, InboundMsg, Msg, Transport, TransportStatus } from './types';

export type BluetoothMac = { id: string; name: string };

// Every write is a write WITH response (ATT reply), moves included.
// Write-without-response deadlocked: ble-plx only writes once
// canSendWriteWithoutResponse is true and otherwise waits for
// peripheralIsReady(toSendWriteWithoutResponse:), but CoreBluetooth only
// sends that after a write was attempted while not ready. Once the buffer
// filled (a few moves into real motion) nothing was ever written again.
// With response there is always a completion; one write is in flight and
// moves arriving meanwhile merge in the outbox (~30-60 Hz on a 15-30 ms
// connection interval).
const WRITE_TIMEOUT_MS = 1000;

export const displayName = (advertised: string | null | undefined): string => {
  const n = (advertised ?? '').trim();
  return n.startsWith(MAC_NAME_PREFIX) ? n.slice(MAC_NAME_PREFIX.length) || 'Mac' : n || 'Mac';
};

// Scan for Macs running AirMouse (Bluetooth on, no Wi-Fi needed). Returns stop().
export function scanBluetoothMacs(onFound: (mac: BluetoothMac) => void, onError: (message: string) => void): () => void {
  let stopped = false;
  const manager = getBleManager();
  const begin = () => {
    if (stopped) return;
    manager
      .startDeviceScan([MAC_SERVICE_UUID], { allowDuplicates: false }, (error, device) => {
        if (error) {
          onError(error.reason ?? error.message);
          return;
        }
        if (device) onFound({ id: device.id, name: displayName(device.localName ?? device.name) });
      })
      .catch((e: unknown) => onError(e instanceof Error ? e.message : String(e)));
  };
  // Scanning before CoreBluetooth is powered on fails, so wait for it.
  const sub = manager.onStateChange((state) => {
    if (state === 'PoweredOn') begin();
    else if (state === 'PoweredOff') onError('Bluetooth is off.');
    else if (state === 'Unauthorized') onError('Bluetooth access is off for AirMouse.');
  }, true);
  return () => {
    stopped = true;
    sub.remove();
    manager.stopDeviceScan();
  };
}

// Protocol v3 JSON over the AirMouse GATT service (docs/spec-v3.md 2b).
export class BleMacTransport implements Transport {
  readonly label: string;
  private id: string;
  onIdChange?: (mac: BluetoothMac) => void;
  private readonly name: string;
  private readonly info: DeviceInfo;
  private device: Device | null = null;
  private wanted = false;
  private outbox = new Outbox();
  private flushing = false;
  private paceTimer: ReturnType<typeof setTimeout> | null = null;
  private lastMoveAt = 0;
  // Debug counters (writes, errors, timeouts).
  stats = { writes: 0, errors: 0, timeouts: 0, lastError: '', mtu: 0, inFlight: 0 };
  private tx = 0;
  private retry: ReturnType<typeof setTimeout> | null = null;
  private subs: Subscription[] = [];
  private listeners = new Set<(s: TransportStatus, detail?: string) => void>();
  private messageListeners = new Set<(m: InboundMsg) => void>();

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
    this.wanted = true;
    this.open();
  }

  private async open() {
    if (this.retry) clearTimeout(this.retry);
    this.retry = null;
    this.emit('connecting');
    const manager = getBleManager();
    try {
      const state = await manager.state();
      if (state !== 'PoweredOn') {
        // Unknown/Resetting right after launch: wait for power-on and retry.
        if (state === 'PoweredOff') this.emit('error', 'Turn on Bluetooth to connect.');
        if (state === 'Unauthorized') this.emit('error', 'Allow Bluetooth for AirMouse in Settings.');
        this.scheduleRetry(1500);
        return;
      }
      let d: Device;
      try {
        d = await manager.connectToDevice(this.id, { timeout: 8000 });
      } catch (e) {
        // Macs rotate their Bluetooth address, so a remembered id can go stale:
        // find the same Mac by its advertised name and remember the new id.
        const found = await this.findByName(6000);
        if (!found || !this.wanted) throw e;
        this.id = found;
        this.onIdChange?.({ id: found, name: this.name });
        d = await manager.connectToDevice(found, { timeout: 8000 });
      }
      if (!this.wanted) {
        d.cancelConnection().catch(() => {});
        return;
      }
      await d.discoverAllServicesAndCharacteristics();
      this.stats.mtu = d.mtu; // stale on iOS right after connect (23); bluetoothd shows the real one
      this.device = d;
      this.subs.push(
        d.onDisconnected(() => {
          this.device = null;
          this.dropSubs();
          if (this.wanted) {
            this.emit('connecting');
            this.scheduleRetry(1000);
          }
        }),
        d.monitorCharacteristicForService(MAC_SERVICE_UUID, MAC_TX_UUID, (error, ch) => {
          if (error || !ch?.value) return;
          const m = decodeInbound(unframe(ch.value));
          if (m) this.messageListeners.forEach((cb) => cb(m));
        }),
      );
      this.outbox.clear();
      this.outbox.push(helloMessage(this.info));
      this.flush();
      this.emit('open');
    } catch {
      if (!this.wanted) return;
      this.emit('error', `Can’t reach ${this.name} over Bluetooth. Keep AirMouse open on the Mac.`);
      this.scheduleRetry(2500);
    }
  }

  private findByName(timeoutMs: number): Promise<string | null> {
    return new Promise((resolve) => {
      let stop: (() => void) | null = null;
      const timer = setTimeout(() => {
        stop?.();
        resolve(null);
      }, timeoutMs);
      stop = scanBluetoothMacs(
        (mac) => {
          if (mac.name !== this.name) return;
          clearTimeout(timer);
          stop?.();
          resolve(mac.id);
        },
        () => {},
      );
    });
  }

  private scheduleRetry(ms: number) {
    if (!this.wanted) return;
    this.retry = setTimeout(() => this.open(), ms);
  }

  private dropSubs() {
    this.subs.forEach((s) => s.remove());
    this.subs = [];
  }

  close() {
    this.wanted = false;
    if (this.retry) clearTimeout(this.retry);
    this.retry = null;
    this.dropSubs();
    this.outbox.clear();
    if (this.paceTimer) clearTimeout(this.paceTimer);
    this.paceTimer = null;
    const d = this.device;
    this.device = null;
    if (d) d.cancelConnection().catch(() => {});
    else getBleManager().cancelDeviceConnection(this.id).catch(() => {});
    this.emit('idle');
  }

  debugStats() {
    const s = this.stats;
    return { link: this.device ? 'connected' : 'down', queued: this.outbox.size, 'in flight': s.inFlight, written: s.writes, failed: s.errors, timeouts: s.timeouts, 'last error': s.lastError };
  }

  send(msg: Msg): boolean {
    if (!this.device) return false;
    this.outbox.push(msg);
    if (!this.flushing && !this.paceTimer) void this.flush();
    return true;
  }

  // ble-plx has no timeout of its own: a lost ATT reply would hold the queue
  // forever. Bound it and move on.
  private write(d: Device, value: string): Promise<unknown> {
    const id = `am-w${++this.tx}`;
    const op = d.writeCharacteristicWithResponseForService(MAC_SERVICE_UUID, MAC_RX_UUID, value, id);
    let timer: ReturnType<typeof setTimeout> | null = null;
    const limit = new Promise((_, reject) => {
      timer = setTimeout(() => {
        this.stats.timeouts += 1;
        getBleManager().cancelTransaction(id);
        reject(new Error('write timed out'));
      }, WRITE_TIMEOUT_MS);
    });
    return Promise.race([op, limit]).finally(() => timer && clearTimeout(timer));
  }

  // One write at a time (ble-plx waits for canSendWriteWithoutResponse, so
  // this is the back-pressure). Moves are paced to ~60 Hz; moves arriving in
  // between merge into the queued one.
  private async flush() {
    if (this.flushing) return;
    this.flushing = true;
    try {
      while (this.device) {
        const head = this.outbox.peek();
        if (!head) break;
        if (head.t === 'move') {
          const wait = moveWait(Date.now(), this.lastMoveAt);
          if (wait > 0) {
            this.paceTimer = setTimeout(() => {
              this.paceTimer = null;
              void this.flush();
            }, wait);
            break;
          }
        }
        this.outbox.shift();
        const d = this.device;
        const value = frame(head);
        try {
          if (head.t === 'move') this.lastMoveAt = Date.now();
          this.stats.inFlight = 1;
          await this.write(d, value);
          this.stats.writes += 1;
        } catch (e) {
          // The message is dropped, the loop goes on; a lost link is handled by onDisconnected.
          this.stats.errors += 1;
          this.stats.lastError = e instanceof Error ? e.message : String(e);
        } finally {
          this.stats.inFlight = 0;
        }
      }
    } finally {
      this.flushing = false;
    }
  }
}
