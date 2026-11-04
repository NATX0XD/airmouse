import { AirMouseSocket } from '../../modules/airmouse-discovery';

// Minimal text WebSocket. On iOS it is the native Network.framework socket
// with TCP_NODELAY (no Nagle bunching of 100 Hz moves); elsewhere the JS one.
export type MiniSocket = {
  send(text: string): boolean;
  close(): void;
  onopen?: () => void;
  onmessage?: (text: string) => void;
  // error = it failed / dropped; undefined = closed normally.
  onclose?: (error?: string) => void;
};

let nextId = 0;

function nativeSocket(url: string): MiniSocket | null {
  const native = AirMouseSocket;
  if (!native) return null;
  const id = `s${++nextId}`;
  let open = false;
  let done = false;
  const s: MiniSocket = {
    send(text) {
      if (!open) return false;
      native.send(id, text);
      return true;
    },
    close() {
      if (done) return;
      done = true;
      open = false;
      subs.forEach((x) => x.remove());
      native.close(id);
    },
  };
  const subs = [
    native.addListener('onSocketOpen', (e) => {
      if (e.id !== id || done) return;
      open = true;
      s.onopen?.();
    }),
    native.addListener('onSocketMessage', (e) => {
      if (e.id === id && !done) s.onmessage?.(e.text);
    }),
    native.addListener('onSocketClose', (e) => {
      if (e.id !== id || done) return;
      done = true;
      open = false;
      subs.forEach((x) => x.remove());
      s.onclose?.(e.error);
    }),
  ];
  native.open(id, url);
  return s;
}

function jsSocket(url: string): MiniSocket {
  const ws = new WebSocket(url);
  let failed = false;
  const s: MiniSocket = {
    send(text) {
      if (ws.readyState !== WebSocket.OPEN) return false;
      ws.send(text);
      return true;
    },
    close() {
      ws.onclose = null;
      ws.close();
    },
  };
  ws.onopen = () => s.onopen?.();
  ws.onmessage = (e) => s.onmessage?.(String(e.data));
  ws.onerror = () => {
    failed = true;
  };
  ws.onclose = () => s.onclose?.(failed ? 'error' : undefined);
  return s;
}

// Throws on a malformed URL (JS fallback only).
export function openSocket(url: string): MiniSocket {
  return nativeSocket(url) ?? jsSocket(url);
}
