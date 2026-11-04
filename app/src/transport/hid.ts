import { AirMouseHid } from '../../modules/airmouse-hid/src/AirMouseHidModule';
import { ReportEncoder } from './report';
import type { Msg, Transport, TransportStatus } from './types';

export class HidTransport implements Transport {
  readonly label = 'Bluetooth HID';
  private readonly encoder: ReportEncoder;
  private connected = false;
  private listeners = new Set<(s: TransportStatus, detail?: string) => void>();
  constructor(screenW = 1920, screenH = 1080) { this.encoder = new ReportEncoder(screenW, screenH); }
  onStatus(cb: (s: TransportStatus, detail?: string) => void) { this.listeners.add(cb); return () => this.listeners.delete(cb); }
  private emit(s: TransportStatus, detail?: string) { this.listeners.forEach((cb) => cb(s, detail)); }
  async connect() {
    this.emit('connecting');
    try {
      if (!AirMouseHid?.isSupported()) throw new Error('Bluetooth HID isn’t available on this device. Try the BLE dongle.');
      const hid = AirMouseHid;
      await hid.register();
      const devices = hid.getBondedDevices();
      if (devices.length === 0) throw new Error('No paired devices.');
      await hid.connect(devices[0].address);
      this.connected = true;
      this.emit('open');
    } catch (e) { this.emit('error', e instanceof Error ? e.message : 'Bluetooth HID isn’t available. Try the BLE dongle.'); }
  }
  close() { AirMouseHid?.disconnect().catch(() => {}); this.connected = false; this.emit('idle'); }
  send(msg: Msg) { if (!this.connected) return; this.encoder.encode(msg).forEach((r) => AirMouseHid?.send([...r]).catch(() => {})); }
}
