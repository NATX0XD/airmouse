// QR payload and typed-address parsing. Pure, no React Native.
//   airmouse://connect?host=192.168.1.20&port=8765&name=Nattakit%27s%20MacBook%20Pro

export const DEFAULT_PORT = 8765;

export type MacAddress = { host: string; port: number; name?: string };

const HOST_RE = /^(?:[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*|\[[0-9a-fA-F:.]+\])$/;

function validPort(v: string | null | undefined): number | null {
  if (v === null || v === undefined || v === '') return DEFAULT_PORT;
  if (!/^\d{1,5}$/.test(v)) return null;
  const n = Number(v);
  return n >= 1 && n <= 65535 ? n : null;
}

function decode(v: string): string {
  try {
    return decodeURIComponent(v.replace(/\+/g, ' '));
  } catch {
    return v;
  }
}

function query(qs: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of qs.split('&')) {
    if (!part) continue;
    const i = part.indexOf('=');
    const k = decode(i < 0 ? part : part.slice(0, i));
    out[k] = i < 0 ? '' : decode(part.slice(i + 1));
  }
  return out;
}

export function parseConnectUrl(data: string): MacAddress | null {
  const m = /^airmouse:\/\/connect\/?\?(.*)$/i.exec(data.trim());
  if (!m) return null;
  const q = query(m[1].split('#')[0]);
  const host = (q.host ?? '').trim();
  if (!host || !HOST_RE.test(host)) return null;
  const port = validPort(q.port?.trim());
  if (port === null) return null;
  const name = q.name?.trim();
  return name ? { host, port, name } : { host, port };
}

// "192.168.1.20", "192.168.1.20:9000", "mac.local", optional ws:// prefix.
export function parseAddress(text: string, portText?: string): MacAddress | null {
  let t = text.trim().replace(/^wss?:\/\//i, '').replace(/\/+$/, '');
  if (!t) return null;
  let portPart: string | undefined = portText?.trim() || undefined;
  const hp = /^([^:]+):(\d+)$/.exec(t);
  if (hp) {
    t = hp[1];
    portPart ??= hp[2];
  }
  if (!HOST_RE.test(t)) return null;
  const port = validPort(portPart);
  return port === null ? null : { host: t, port };
}
