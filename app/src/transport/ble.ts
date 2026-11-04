import type { Device, Subscription } from 'react-native-ble-plx';
import { getBleManager as getManager } from './bleManager';
import { BLE_REPORT_CHARACTERISTIC_UUID as AIRMOUSE_REPORT_UUID, BLE_SERVICE_UUID as AIRMOUSE_SERVICE_UUID } from './bleIds';
import { ReportEncoder } from './report';
import type { Msg, Transport, TransportStatus } from './types';

const toBase64 = (bytes: Uint8Array) => {
  let text = '';
  bytes.forEach((b) => { text += String.fromCharCode(b); });
  return globalThis.btoa(text);
};

export class BleTransport implements Transport {
  readonly label = 'AirMouse-Dongle';
  private device: Device | null = null;
  private wanted = false;
  private reports: Uint8Array[] = [];
  private flushTimer: ReturnType<typeof setTimeout> | null = null;
  private disconnectSub: Subscription | null = null;
  private listeners = new Set<(s: TransportStatus, detail?: string) => void>();
  private readonly encoder: ReportEncoder;

  constructor(screenW = 1920, screenH = 1080) { this.encoder = new ReportEncoder(screenW, screenH); }
  onStatus(cb: (s: TransportStatus, detail?: string) => void) { this.listeners.add(cb); return () => this.listeners.delete(cb); }
  private emit(s: TransportStatus, detail?: string) { this.listeners.forEach((cb) => cb(s, detail)); }
  connect() { this.wanted = true; this.emit('connecting'); getManager().startDeviceScan([AIRMOUSE_SERVICE_UUID], null, (error, device) => {
    if (error) { this.emit('error', 'Can’t scan for the dongle. Check Bluetooth access.'); return; }
    if (device) { getManager().stopDeviceScan(); this.open(device); }
  }); }
  private async open(device: Device) {
    try {
      this.device = await device.connect();
      if (device.id) { try { await this.device.requestMTU(185); } catch { /* iOS or old Android may reject MTU */ } }
      await this.device.discoverAllServicesAndCharacteristics();
      this.disconnectSub = this.device.onDisconnected(() => { this.device = null; if (this.wanted) { this.emit('connecting'); setTimeout(() => this.connect(), 800); } });
      this.emit('open');
    } catch { this.emit('error', 'Couldn’t connect to the dongle.'); }
  }
  close() { this.wanted = false; getManager().stopDeviceScan(); this.disconnectSub?.remove(); this.disconnectSub = null; this.device?.cancelConnection().catch(() => {}); this.device = null; this.emit('idle'); }
  send(msg: Msg) { this.reports.push(...this.encoder.encode(msg)); if (!this.flushTimer) this.flushTimer = setTimeout(() => this.flush(), 0); }
  private async flush() {
    this.flushTimer = null;
    const reports = this.reports.splice(0);
    if (!this.device || reports.length === 0) return;
    const bytes = new Uint8Array(reports.length * 5);
    reports.forEach((r, i) => bytes.set(r, i * 5));
    try { await this.device.writeCharacteristicWithoutResponseForService(AIRMOUSE_SERVICE_UUID, AIRMOUSE_REPORT_UUID, toBase64(bytes)); }
    catch { this.emit('error', 'Lost the dongle connection.'); }
  }
}
