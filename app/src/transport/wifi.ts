import { decodeInbound, encode, helloMessage } from './protocol';
import type { DeviceInfo, InboundMsg, Msg, Transport, TransportStatus } from './types';
import { openSocket, type MiniSocket } from './socket';

// WebSocket to the AirMouse Mac app (protocol v3), TCP_NODELAY on iOS (socket.ts). Reconnects by itself until
// close() is called.
export class WifiTransport implements Transport {
  readonly label: string;
  private url: string;
  private device: DeviceInfo;
  private ws: MiniSocket | null = null;
  private listeners = new Set<(s: TransportStatus, detail?: string) => void>();
  private messageListeners = new Set<(m: InboundMsg) => void>();
  private wanted = false;
  private retry: ReturnType<typeof setTimeout> | null = null;

  constructor(host: string, port: number, device: DeviceInfo) {
    const h = host.includes(':') && !host.startsWith('[') ? `[${host}]` : host;
    this.url = `ws://${h}:${port}`;
    this.label = `${host}:${port}`;
    this.device = device;
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

  private open() {
    if (this.retry) clearTimeout(this.retry);
    this.retry = null;
    this.emit('connecting');
    let ws: MiniSocket;
    try {
      ws = openSocket(this.url);
    } catch {
      this.emit('error', 'That address doesn’t look right.');
      return;
    }
    this.ws = ws;
    ws.onopen = () => {
      ws.send(encode(helloMessage(this.device)));
      this.emit('open');
    };
    ws.onmessage = (text) => {
      const m = decodeInbound(text);
      if (m) this.messageListeners.forEach((cb) => cb(m));
    };
    ws.onclose = (error) => {
      if (this.ws !== ws) return;
      if (error) this.emit('error', 'Can’t reach the Mac. Check that both are on the same Wi-Fi.');
      this.ws = null;
      if (this.wanted) {
        this.emit('connecting');
        this.retry = setTimeout(() => this.open(), 1500);
      } else {
        this.emit('idle');
      }
    };
  }

  close() {
    this.wanted = false;
    if (this.retry) clearTimeout(this.retry);
    this.retry = null;
    const ws = this.ws;
    this.ws = null;
    ws?.close();
    this.emit('idle');
  }

  send(msg: Msg): boolean {
    return this.ws?.send(encode(msg)) ?? false;
  }
}
