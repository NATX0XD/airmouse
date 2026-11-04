import type { Device, Subscription } from 'react-native-ble-plx';
import { getBleManager } from './bleManager';
import { MAC_NAME_PREFIX, MAC_RX_UUID, MAC_SERVICE_UUID, MAC_TX_UUID } from './bleIds';
import { frame, Outbox, unframe } from './bleFraming';
import { decodeInbound, helloMessage } from './protocol';
import type { DeviceInfo, InboundMsg, Msg, Transport, TransportStatus } from './types';

export type BluetoothMac = { id: string; name: string };

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
  private writing = false;
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
    const d = this.device;
    this.device = null;
    if (d) d.cancelConnection().catch(() => {});
    else getBleManager().cancelDeviceConnection(this.id).catch(() => {});
    this.emit('idle');
  }

  send(msg: Msg) {
    if (!this.device) return;
    this.outbox.push(msg);
    // Defer to the end of this JS tick so one gyro tick = at most one move write.
    if (!this.writing) {
      this.writing = true;
      setTimeout(() => this.flush(), 0);
    }
  }

  private async flush() {
    this.writing = true;
    try {
      let msg = this.outbox.shift();
      while (msg && this.device) {
        const d = this.device;
        const value = frame(msg);
        if (msg.t === 'move') await d.writeCharacteristicWithoutResponseForService(MAC_SERVICE_UUID, MAC_RX_UUID, value);
        else await d.writeCharacteristicWithResponseForService(MAC_SERVICE_UUID, MAC_RX_UUID, value);
        msg = this.outbox.shift();
      }
    } catch {
      // A failed write usually means the link dropped; onDisconnected reconnects.
    } finally {
      this.writing = false;
    }
  }
}
