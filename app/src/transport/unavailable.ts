import type { Msg, Transport, TransportStatus } from './types';

export class UnavailableTransport implements Transport {
  readonly label: string;
  private listeners = new Set<(s: TransportStatus, detail?: string) => void>();
  constructor(label: string, private reason: string) { this.label = label; }
  onStatus(cb: (s: TransportStatus, detail?: string) => void) { this.listeners.add(cb); return () => this.listeners.delete(cb); }
  connect() { this.listeners.forEach((cb) => cb('error', this.reason)); }
  close() { this.listeners.forEach((cb) => cb('idle')); }
  send(_msg: Msg) {}
}
