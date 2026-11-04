import { useCallback, useEffect, useRef, useState } from 'react';
import { Gyroscope } from 'expo-sensors';
import * as Device from 'expo-device';
import * as Haptics from 'expo-haptics';
import { MAX_DT, MIN_MOVE, MotionEngine, type GyroSample, type MotionSettings } from './motion/engine';
import { PauseLatch, type PauseOwner } from './motion/pause';
import { FlickDetector } from './motion/gesture';
import { pointerActive } from './motion/pointer';
import { bodySizeFor } from './device/dimensions';
import type { AppSettings, TransportKind } from './settings';
import type { DeviceInfo, InboundMsg, Msg, ScreenInfo, Transport, TransportStatus } from './transport/types';
import { WifiTransport } from './transport/wifi';
import { BleTransport } from './transport/ble';
import { HidTransport } from './transport/hid';
import { BleMacTransport, type BluetoothMac } from './transport/bleMac';

export type ConnectTarget =
  | { kind: 'wifi'; host: string; port: number; name?: string }
  | { kind: 'bluetooth'; id: string; name: string }
  | { kind: 'ble' }
  | { kind: 'hid' };

const GYRO_INTERVAL_MS = 10; // 100 Hz (CMMotionManager gyroUpdateInterval honours it)
const HISTORY = 250; // samples kept for the live chart (~2.5 s)
const round2 = (v: number) => Math.round(v * 100) / 100 || 0;

// Settings > Diagnostics snapshot (docs/spec-v3.md 4a.4).
export type Diagnostics = {
  kind: TransportKind | null;
  status: TransportStatus;
  paused: boolean;
  pausedBy: string[];
  touching: boolean;
  mode: string;
  gyroHz: number;
  gaps: number; // samples dropped by the engine (gap > MAX_DT)
  sent: Record<string, number>; // per type, actually handed to an open transport
  dropped: number; // send() while the transport was not open
  lastDx: number;
  lastDy: number;
  lastMoveAgoMs: number | null;
  link: Record<string, string | number> | null; // transport counters (Bluetooth)
};

export function deviceInfo(): DeviceInfo {
  try {
    const size = bodySizeFor(Device.modelId, Device.modelName);
    return { name: Device.deviceName ?? 'iPhone', model: Device.modelName ?? 'iPhone', ...size };
  } catch {
    return { name: 'iPhone', model: 'iPhone', ...bodySizeFor(null) };
  }
}

type Options = { onMessage?: (m: InboundMsg) => void; onBluetoothId?: (mac: BluetoothMac) => void };

// Owns the gyroscope stream, the motion engine and the active transport.
export function useAirMouse(settings: AppSettings, options: Options = {}) {
  const engine = useRef(new MotionEngine(settings.motion));
  const transport = useRef<Transport | null>(null);
  const touching = useRef(false);
  const pauses = useRef(new PauseLatch());
  // Calibration verify step: clutch forced on (no hold needed) while pointing
  // is otherwise paused, using the not-yet-saved settings in `override`.
  const aiming = useRef(false);
  const override = useRef<MotionSettings | null>(null);
  const savedMotion = useRef(settings.motion);
  const modeRef = useRef(settings.mode);
  const history = useRef<GyroSample[]>([]);
  const flick = useRef(new FlickDetector());
  const gyroListeners = useRef(new Set<(s: GyroSample) => void>());
  const onMessage = useRef(options.onMessage);
  const onBluetoothId = useRef(options.onBluetoothId);
  const [kind, setKind] = useState<TransportKind | null>(null);
  const kindRef = useRef<TransportKind | null>(null);
  const lastStatus = useRef<TransportStatus>('idle');
  const [status, setStatus] = useState<TransportStatus>('idle');
  const [detail, setDetail] = useState<string | undefined>();
  const [gyroAvailable, setGyroAvailable] = useState<boolean | null>(null);
  const [screen, setScreen] = useState<ScreenInfo | null>(null);
  const stats = useRef({ sent: {} as Record<string, number>, dropped: 0, lastDx: 0, lastDy: 0, lastMoveAt: 0, gaps: 0, lastT: 0, ticks: [] as number[] });

  // Every message goes through here so Diagnostics can count it.
  const sendRaw = useCallback((m: Msg) => {
    const t = transport.current;
    const st = stats.current;
    const key = m.t === 'calib' ? `calib.${m.step}` : m.t;
    if (!t || t.send(m) === false) {
      st.dropped += 1;
      return;
    }
    st.sent[key] = (st.sent[key] ?? 0) + 1;
    if (m.t === 'move') {
      st.lastDx = m.dx;
      st.lastDy = m.dy;
      st.lastMoveAt = Date.now();
    }
  }, []);

  useEffect(() => {
    onMessage.current = options.onMessage;
    onBluetoothId.current = options.onBluetoothId;
  }, [options.onMessage, options.onBluetoothId]);

  useEffect(() => {
    savedMotion.current = settings.motion;
    engine.current.settings = override.current ?? settings.motion;
    modeRef.current = settings.mode;
  }, [settings.motion, settings.mode]);

  useEffect(() => {
    let sub: { remove(): void } | null = null;
    let cancelled = false;
    Gyroscope.isAvailableAsync()
      .then((ok) => {
        if (cancelled) return;
        setGyroAvailable(ok);
        if (!ok) return;
        Gyroscope.setUpdateInterval(GYRO_INTERVAL_MS);
        // Coalesce: samples handled in the same JS tick go out as one move
        // (summed). Sub-0.01 pt leftovers are carried, not dropped. No
        // allocation or setState per sample beyond the message itself.
        const acc = { dx: 0, dy: 0, queued: false };
        const flush = () => {
          acc.queued = false;
          const dx = round2(acc.dx);
          const dy = round2(acc.dy);
          if (Math.abs(dx) < MIN_MOVE && Math.abs(dy) < MIN_MOVE) return;
          acc.dx -= dx;
          acc.dy -= dy;
          sendRaw({ t: 'move', dx, dy });
        };
        const move = (dx: number, dy: number) => {
          if (dx === 0 && dy === 0) return;
          acc.dx += dx;
          acc.dy += dy;
          if (!acc.queued) {
            acc.queued = true;
            setImmediate(flush);
          }
        };
        let current: GyroSample | null = null;
        const notify = (cb: (s: GyroSample) => void) => {
          // A throwing listener must never stop the pointer.
          try {
            if (current) cb(current);
          } catch {
            // ignored on purpose
          }
        };
        sub = Gyroscope.addListener((s) => {
          const st = stats.current;
          const now = Date.now();
          st.ticks.push(now);
          while (st.ticks.length && now - st.ticks[0] > 1000) st.ticks.shift();
          if (st.lastT && s.timestamp - st.lastT > MAX_DT) st.gaps += 1;
          st.lastT = s.timestamp;
          const h = history.current;
          h.push(s);
          if (h.length > HISTORY) h.shift();
          if (gyroListeners.current.size) {
            current = s;
            gyroListeners.current.forEach(notify);
            current = null;
          }

          if (aiming.current) {
            const a = engine.current.update(s, true);
            move(a.dx, a.dy);
            return;
          }
          if (pauses.current.paused) {
            engine.current.update(s, false); // keep filters warm
            acc.dx = 0;
            acc.dy = 0;
            return;
          }
          const active = pointerActive(modeRef.current, touching.current);
          if (settings.flickSlides && modeRef.current === 'hold' && !touching.current) {
            const direction = flick.current.update(s);
            if (direction) {
              sendRaw({ t: 'key', k: direction });
              Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
            }
          }
          const out = engine.current.update(s, active);
          if (!active) {
            acc.dx = 0; // clutch released: don't leak a leftover into the next hold
            acc.dy = 0;
          }
          move(out.dx, out.dy);
        });
      })
      .catch(() => !cancelled && setGyroAvailable(false));
    return () => {
      cancelled = true;
      sub?.remove();
    };
  }, [settings.flickSlides, sendRaw]);

  const disconnect = useCallback(() => {
    const t = transport.current;
    transport.current = null;
    t?.close();
    lastStatus.current = 'idle';
    setKind(null);
    setStatus('idle');
    setDetail(undefined);
  }, []);

  const connect = useCallback(
    (target: ConnectTarget) => {
      disconnect();
      let t: Transport;
      if (target.kind === 'wifi') t = new WifiTransport(target.host.trim(), target.port, deviceInfo());
      else if (target.kind === 'bluetooth') {
        const b = new BleMacTransport({ id: target.id, name: target.name }, deviceInfo());
        b.onIdChange = (mac) => onBluetoothId.current?.(mac);
        t = b;
      } else if (target.kind === 'ble') t = new BleTransport(settings.screenW, settings.screenH);
      else t = new HidTransport(settings.screenW, settings.screenH);
      transport.current = t;
      kindRef.current = target.kind;
      setKind(target.kind);
      t.onStatus((s, d) => {
        if (transport.current !== t) return;
        if (s !== lastStatus.current) {
          if (s === 'open') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
          if (s === 'error' && lastStatus.current !== 'connecting') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
        }
        lastStatus.current = s;
        setStatus(s);
        setDetail(d);
      });
      t.onMessage?.((m) => {
        if (transport.current !== t) return;
        if (m.t === 'screen') setScreen({ w: m.w, h: m.h, scale: m.scale, wMm: m.wMm, hMm: m.hMm, name: m.name });
        onMessage.current?.(m);
      });
      t.connect();
    },
    [disconnect, settings.screenW, settings.screenH],
  );

  useEffect(() => disconnect, [disconnect]);

  const send = useCallback((m: Msg) => sendRaw(m), [sendRaw]);

  const setTouching = useCallback((v: boolean) => {
    touching.current = v;
  }, []);

  // Calibration takes over the gyro: no cursor motion, no flicks. Owners
  // are idempotent (see motion/pause.ts); on resume the clutch and the
  // filters start clean.
  const setPaused = useCallback((owner: PauseOwner, v: boolean) => {
    if (pauses.current.set(owner, v) && !v) {
      touching.current = false;
      engine.current.reset();
    }
  }, []);

  const setAiming = useCallback((v: boolean) => {
    aiming.current = v;
  }, []);

  // null = back to the saved settings.
  const setMotionOverride = useCallback((m: MotionSettings | null) => {
    override.current = m;
    engine.current.settings = m ?? savedMotion.current;
  }, []);

  const diagnostics = useCallback((): Diagnostics => {
    const st = stats.current;
    return {
      kind: transport.current ? kindRef.current : null,
      status: lastStatus.current,
      paused: pauses.current.paused,
      pausedBy: pauses.current.list(),
      touching: touching.current,
      mode: modeRef.current,
      gyroHz: st.ticks.length,
      gaps: st.gaps,
      sent: { ...st.sent },
      dropped: st.dropped,
      lastDx: st.lastDx,
      lastDy: st.lastDy,
      lastMoveAgoMs: st.lastMoveAt ? Date.now() - st.lastMoveAt : null,
      link: transport.current?.debugStats?.() ?? null,
    };
  }, []);

  const addGyroListener = useCallback((cb: (s: GyroSample) => void) => {
    gyroListeners.current.add(cb);
    return () => {
      gyroListeners.current.delete(cb);
    };
  }, []);

  return { kind, status, detail, gyroAvailable, screen, connect, disconnect, send, setTouching, setPaused, setAiming, setMotionOverride, addGyroListener, history, diagnostics };
}

export type AirMouse = ReturnType<typeof useAirMouse>;
