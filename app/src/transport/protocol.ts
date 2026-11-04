import { CALIB_TARGET_IDS, type CalibTarget, type DeviceInfo, type HelloMsg, type InboundMsg, type Msg, type PracticeInbound } from './types.ts';

// Protocol v3 JSON codec. Pure, no React Native.

export const PROTOCOL_VERSION = 3;

export function helloMessage(device: DeviceInfo): HelloMsg {
  return { t: 'hello', v: PROTOCOL_VERSION, app: 'airmouse', device };
}

export function encode(msg: Msg | HelloMsg): string {
  return JSON.stringify(msg);
}

const positive = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v) && v > 0;

const count = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v) && v >= 0;

const isTarget = (v: unknown): v is CalibTarget => typeof v === 'string' && (CALIB_TARGET_IDS as readonly string[]).includes(v);

// Returns null for anything we do not understand: unknown `t`, unknown calib
// steps, malformed JSON or missing fields. Unknown extra fields are dropped.
export function decodeInbound(raw: unknown): InboundMsg | null {
  let m: Record<string, unknown>;
  try {
    const parsed: unknown = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!parsed || typeof parsed !== 'object') return null;
    m = parsed as Record<string, unknown>;
  } catch {
    return null;
  }
  if (m.t === 'screen') {
    if (!positive(m.w) || !positive(m.h)) return null;
    const out: InboundMsg = { t: 'screen', w: m.w, h: m.h };
    if (positive(m.scale)) out.scale = m.scale;
    if (positive(m.wMm) && positive(m.hMm)) {
      out.wMm = m.wMm;
      out.hMm = m.hMm;
    }
    if (typeof m.name === 'string' && m.name.trim()) out.name = m.name.trim();
    return out;
  }
  if (m.t === 'calib' && (m.step === 'request' || m.step === 'cancel')) return { t: 'calib', step: m.step };
  if (m.t === 'calib' && m.step === 'hit' && isTarget(m.target)) return { t: 'calib', step: 'hit', target: m.target };
  if (m.t === 'focus' && typeof m.editable === 'boolean') return { t: 'focus', editable: m.editable };
  if (m.t === 'practice' && (m.step === 'running' || m.step === 'result' || m.step === 'stop')) {
    const out: PracticeInbound = { t: 'practice', step: m.step };
    if (count(m.hits)) out.hits = m.hits;
    if (count(m.total)) out.total = m.total;
    if (count(m.ms)) out.ms = m.ms;
    return out;
  }
  return null;
}
