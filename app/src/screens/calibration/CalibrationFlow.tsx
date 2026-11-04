import { useCallback, useEffect, useRef, useState } from 'react';
import { Animated, Modal, Pressable, StyleSheet, View, useAnimatedValue } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Haptics from 'expo-haptics';
import { Accelerometer } from 'expo-sensors';
import { AirMouseProximity } from '../../../modules/airmouse-discovery';
import { AngleIntegrator, CALIB_TARGETS, SENS_MAX, SENS_MIN, TARGET_NAMES, calibrateBias, evaluateCorners, scaleSpeed, type Corners } from '../../motion/calibration';
import type { GyroSample, MotionSettings } from '../../motion/engine';
import { PlacementDetector, placementHint, type Accel, type PlacementState } from '../../motion/placement';
import { shouldEmit } from '../../motion/stillness';
import type { CalibTarget, Msg } from '../../transport/types';
import { Card, Icon, PrimaryButton, SecondaryButton, SliderRow, T } from '../../ui/components';
import { space, usePalette, useReduceMotion } from '../../ui/tokens';
import { PlaceIllustration, PointIllustration } from './Illustrations';
import { Illustration } from '../../ui/Illustration';

export type CalibStep = 'place' | 'placed' | 'point' | 'retry' | 'verify';

export type CalibResult = { biasX: number; biasY: number; biasZ: number; sensitivity: number; sensitivityY: number };

type Props = {
  visible: boolean;
  connected: boolean;
  gyroAvailable: boolean | null;
  motion: MotionSettings;
  screenW: number;
  screenH: number;
  send: (m: Msg) => void;
  addGyroListener: (cb: (s: GyroSample) => void) => () => void;
  onFinish: (r: CalibResult) => void;
  // finished = a result was saved (App shows the "Calibrated" toast).
  onClose: (finished: boolean) => void;
  // Live cursor, clutch forced on, with these settings (saved ones while
  // aiming at the corners, the measured ones during verify). null = stop.
  onVerify?: (m: MotionSettings | null) => void;
  // Latest `calib hit` from the Mac; `n` changes on every message.
  hit?: { target: CalibTarget; n: number } | null;
  preview?: { step: CalibStep; progress?: number; result?: CalibResult };
};

const PLACE_HZ_MS = 100; // `calib place` at ~10 Hz
const UI_MS = 50; // progress redraw
const STILL_SPREAD = 0.1; // rad/s, hand-held against a screen
const NO_SENSOR_ADVANCE_MS = 1000; // no proximity sensor: advance on a timer
const LIFT_MIN_MS = 500; // show "Great." at least this long before lift-advance

type Place = Pick<PlacementState, 'progress' | 'still' | 'near' | 'upright' | 'done'>;
const PLACE_IDLE: Place = { progress: 0, still: false, near: false, upright: false, done: false };
type Speed = { sensitivity: number; sensitivityY: number };
type Retry = { axis: 'x' | 'y'; reason: 'small' | 'large'; degreesX: number; degreesY: number };

// Calibration v3 (docs/spec-v3.md 4a): place -> lift -> point at centre and
// the 4 corners (tap each) -> verify with the new speed -> Done.
// Pointing stays paused (App, motion/pause.ts) from start to verify; the
// verify step drives the cursor through `onVerify`.
export function CalibrationFlow(p: Props) {
  const c = usePalette();
  const insets = useSafeAreaInsets();
  const reduceMotion = useReduceMotion();
  const [step, setStep] = useState<CalibStep>(p.preview?.step ?? 'place');
  const [place, setPlace] = useState<Place>(p.preview ? { ...PLACE_IDLE, progress: p.preview.progress ?? 0, near: true, upright: true, still: true } : PLACE_IDLE);
  const [note, setNote] = useState<string | null>(null);
  const [targetIdx, setTargetIdx] = useState(0);
  const [hits, setHits] = useState<CalibTarget[]>([]);
  const [speed, setSpeed] = useState<Speed | null>(p.preview?.result ?? null);
  const [retry, setRetry] = useState<Retry | null>(p.preview?.step === 'retry' ? { axis: 'y', reason: 'small', degreesX: 28, degreesY: 4 } : null);
  const [hasProximity, setHasProximity] = useState<boolean | null>(AirMouseProximity ? null : false);

  const stepRef = useRef<CalibStep>('place');
  const targetRef = useRef(0);
  const detector = useRef(new PlacementDetector({ threshold: 0.1, holdSeconds: 2 }));
  const near = useRef(false);
  const proximity = useRef<boolean | null>(null); // null = unknown yet
  const accel = useRef<Accel | null>(null);
  const bias = useRef({ biasX: 0, biasY: 0, biasZ: 0 });
  const angles = useRef(new AngleIntegrator());
  const corners = useRef<Partial<Corners>>({});
  const lastPlace = useRef<number | null>(null);
  const lastFlags = useRef('');
  const lastUi = useRef<number | null>(null);
  const holding = useRef(false);
  const placedAt = useRef(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const finished = useRef(false);
  const closed = useRef(false);
  const sendRef = useRef(p.send);
  const motionRef = useRef(p.motion);
  const screenRef = useRef({ w: p.screenW, h: p.screenH });
  const closeRef = useRef(p.onClose);
  const verifyRef = useRef(p.onVerify);
  useEffect(() => {
    sendRef.current = p.send;
    motionRef.current = p.motion;
    screenRef.current = { w: p.screenW, h: p.screenH };
    closeRef.current = p.onClose;
    verifyRef.current = p.onVerify;
  }, [p.send, p.motion, p.screenW, p.screenH, p.onClose, p.onVerify]);

  const go = useCallback((s: CalibStep) => {
    stepRef.current = s;
    setStep(s);
  }, []);

  const later = useCallback((ms: number, fn: () => void) => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      timer.current = null;
      fn();
    }, ms);
  }, []);

  // Start (or redo) the pointing part at the centre dot.
  const toCenter = useCallback(() => {
    const st = stepRef.current;
    if (st !== 'placed' && st !== 'retry' && st !== 'verify') return;
    sendRef.current({ t: 'calib', step: 'point', target: 'center' });
    angles.current.reset();
    corners.current = {};
    targetRef.current = 0;
    setTargetIdx(0);
    setHits([]);
    setNote(null);
    go('point');
  }, [go]);

  // Fade/slide between steps.
  const enter = useAnimatedValue(1);
  useEffect(() => {
    enter.setValue(0);
    Animated.spring(enter, { toValue: 1, useNativeDriver: true, damping: 20, stiffness: 160 }).start();
  }, [step, enter]);

  const { visible, preview, addGyroListener, hit } = p;
  const live = visible && !preview;
  const placing = step === 'place' || step === 'placed';

  // Step 1 sensors: proximity (screen against the display) + accelerometer
  // (upright). Only on during step 1; always switched off when it ends.
  useEffect(() => {
    if (!live || !placing) return;
    let alive = true;
    const prox = AirMouseProximity;
    let proxSub: { remove(): void } | null = null;
    if (!prox) {
      proximity.current = false;
      near.current = true; // no sensor (Android, iPad, simulator): upright + still only
    } else {
      proxSub = prox.addListener('onProximityChange', (e) => {
        near.current = !!e.near;
      });
      prox
        .setEnabled(true)
        .then((ok) => {
          if (!alive) return;
          proximity.current = ok;
          setHasProximity(ok);
          if (!ok) near.current = true;
          else prox.isNear().then((n) => alive && (near.current = n)).catch(() => {});
        })
        .catch(() => {
          if (!alive) return;
          proximity.current = false;
          near.current = true;
          setHasProximity(false);
        });
    }
    let accelSub: { remove(): void } | null = null;
    Accelerometer.isAvailableAsync()
      .then((ok) => {
        if (!alive) return;
        if (!ok) {
          accel.current = { x: 0, y: -1, z: 0 }; // no accelerometer: don't block on "upright"
          return;
        }
        Accelerometer.setUpdateInterval(50);
        accelSub = Accelerometer.addListener((a) => {
          accel.current = a;
        });
      })
      .catch(() => {});
    return () => {
      alive = false;
      proxSub?.remove();
      prox?.setEnabled(false).catch(() => {});
      accelSub?.remove();
      accel.current = null;
    };
  }, [live, placing]);

  // Session lifecycle: tell the Mac, listen to the gyro. Pointing is paused
  // by App while this flow is open (motion/pause.ts), not from here.
  useEffect(() => {
    if (!live) return;
    // Fresh state per session: the parent remounts this component (new key)
    // every time calibration opens.
    finished.current = false;
    closed.current = false;
    detector.current.reset();
    angles.current.reset();
    corners.current = {};
    lastPlace.current = null;
    lastFlags.current = '';
    holding.current = false;
    stepRef.current = 'place';
    sendRef.current({ t: 'calib', step: 'start' });

    const off = addGyroListener((s) => {
      const st = stepRef.current;
      if (st === 'place') {
        const r = detector.current.update(s, { near: near.current, accel: accel.current });
        const now = Date.now();
        const flags = `${r.still}${r.near}${r.upright}`;
        const changed = flags !== lastFlags.current;
        if (changed || r.done || shouldEmit(now, lastPlace.current, PLACE_HZ_MS)) {
          sendRef.current({ t: 'calib', step: 'place', progress: Number(r.progress.toFixed(3)), still: r.still, near: r.near, upright: r.upright });
          lastPlace.current = now;
          lastFlags.current = flags;
        }
        if (changed || r.done || shouldEmit(now, lastUi.current, UI_MS)) {
          lastUi.current = now;
          setPlace({ progress: r.progress, still: r.still, near: r.near, upright: r.upright, done: r.done });
        }
        // Soft tick when the phone is placed: the screen may be off now.
        const all = r.near && r.upright && r.still;
        if (all && !holding.current) Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Soft);
        holding.current = all;
        if (r.done) {
          const b = calibrateBias(detector.current.stillSamples(), STILL_SPREAD);
          if (!b.ok) {
            detector.current.reset();
            setNote('Hold a little more still.');
            Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
            return;
          }
          bias.current = { biasX: b.biasX, biasY: b.biasY, biasZ: b.biasZ };
          sendRef.current({ t: 'calib', step: 'placed' });
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
          setNote(null);
          placedAt.current = now;
          go('placed');
          // No proximity sensor: nothing to wait for, advance on a timer.
          if (proximity.current !== true) later(NO_SENSOR_ADVANCE_MS, toCenter);
        }
      } else if (st === 'placed') {
        // Lifted off the screen after success: on to pointing.
        if (proximity.current === true && !near.current && Date.now() - placedAt.current > LIFT_MIN_MS) toCenter();
      } else if (st === 'point') {
        // Always integrating; the centre tap resets to zero.
        angles.current.add(s, bias.current);
      }
    });

    return () => {
      off();
      if (timer.current) clearTimeout(timer.current);
      timer.current = null;
      if (!finished.current) sendRef.current({ t: 'calib', step: 'cancel' });
    };
  }, [live, addGyroListener, go, later, toCenter]);

  // Corners (after the centre tap): live cursor with the saved settings and
  // the clutch forced on, so the user sees where they point. The Mac warps the
  // cursor to the centre on `pointed center`. Angles stay gyro-integrated.
  const aimingCorners = live && step === 'point' && targetIdx > 0;
  useEffect(() => {
    if (!aimingCorners) return;
    verifyRef.current?.(motionRef.current);
    return () => verifyRef.current?.(null);
  }, [aimingCorners]);

  // Verify: cursor live with the measured speed, no hold needed.
  const verifyMotion = useCallback((sp: Speed) => ({ ...motionRef.current, ...bias.current, ...sp }), []);
  useEffect(() => {
    if (!live || step !== 'verify' || !speed) return;
    verifyRef.current?.(verifyMotion(speed));
    return () => verifyRef.current?.(null);
  }, [live, step, speed, verifyMotion]);

  // Mac reports the cursor touching a dot during verify.
  useEffect(() => {
    if (!hit || stepRef.current !== 'verify') return;
    setHits((h) => (h.includes(hit.target) ? h : [...h, hit.target]));
    Haptics.selectionAsync();
  }, [hit]);

  // Done button, Cancel, Mac cancel: whichever comes first.
  const close = useCallback(() => {
    if (closed.current) return;
    closed.current = true;
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
    closeRef.current(finished.current);
  }, []);

  const tap = () => {
    if (preview || stepRef.current !== 'point') return;
    const idx = targetRef.current;
    const t = CALIB_TARGETS[idx];
    sendRef.current({ t: 'calib', step: 'pointed', target: t });
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    if (t === 'center') angles.current.reset();
    else corners.current[t] = angles.current.snapshot();
    if (idx < CALIB_TARGETS.length - 1) {
      targetRef.current = idx + 1;
      setTargetIdx(idx + 1);
      sendRef.current({ t: 'calib', step: 'point', target: CALIB_TARGETS[idx + 1] });
      return;
    }
    const r = evaluateCorners(corners.current as Corners, screenRef.current.w, screenRef.current.h);
    if (!r.ok) {
      // Would clamp: don't save a capped speed, ask for another go.
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
      setRetry({ axis: r.axis, reason: r.reason, degreesX: r.degreesX, degreesY: r.degreesY });
      go('retry');
      return;
    }
    sendRef.current({ t: 'calib', step: 'verify' });
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    setSpeed({ sensitivity: r.sensitivity, sensitivityY: r.sensitivityY });
    setHits([]);
    go('verify');
  };

  const done = () => {
    if (!speed) return;
    const r: CalibResult = { ...bias.current, ...speed };
    if (!preview) {
      sendRef.current({ t: 'calib', step: 'done', sensitivity: r.sensitivity, sensitivityY: r.sensitivityY });
      finished.current = true;
      p.onFinish(r);
    }
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    close();
  };

  const target = CALIB_TARGETS[targetIdx];
  const ticked = step === 'verify' ? hits : CALIB_TARGETS.slice(0, step === 'point' ? targetIdx : 0);
  const hint = placementHint(place);
  const stepNo = placing ? 1 : step === 'verify' ? 3 : 2;
  const title =
    step === 'place'
      ? 'Turn Your iPhone Around'
      : step === 'placed'
        ? 'Great.'
        : step === 'point'
          ? targetIdx === 0
            ? 'Point at the Center Dot'
            : `Point at ${TARGET_NAMES[target]}`
          : step === 'retry'
            ? 'Let’s Try That Again'
            : 'Check Your Pointer';
  const axisName = retry?.axis === 'y' ? 'up-and-down' : 'side-to-side';
  const body =
    step === 'place'
      ? 'Hold it flat against the screen, inside the outline, with the display facing the screen.'
      : step === 'placed'
        ? hasProximity
          ? 'Now lift your iPhone and hold it like a remote.'
          : 'Your gyroscope is calibrated.'
        : step === 'point'
          ? 'Hold your iPhone like a remote. Tap anywhere when you’re pointing at the dot on your Mac.'
          : step === 'retry'
            ? `That ${axisName} turn looked too ${retry?.reason === 'large' ? 'big' : 'small'}. Point right at each dot and try again.`
            : 'Move the pointer over each dot on your Mac. No need to hold.';
  const placeChip =
    note ??
    (hint === 'bring'
      ? 'Bring your iPhone to the screen'
      : hint === 'upright'
        ? 'Hold it upright against the screen'
        : hint === 'still'
          ? 'Hold still'
          : `Hold still… ${Math.round(place.progress * 100)}%`);
  const translateY = enter.interpolate({ inputRange: [0, 1], outputRange: [reduceMotion ? 0 : 14, 0] });

  return (
    <Modal visible={p.visible} animationType="slide" presentationStyle="fullScreen" onRequestClose={close}>
      <Pressable
        style={[styles.root, { backgroundColor: c.background, paddingTop: insets.top + space.sm, paddingBottom: insets.bottom + space.lg }]}
        onPress={step === 'point' ? tap : undefined}
        accessible={false}
      >
        <View style={styles.header}>
          <Pressable onPress={close} hitSlop={12} accessibilityRole="button" accessibilityLabel="Cancel" style={{ minWidth: 70 }}>
            <T color={c.tint}>Cancel</T>
          </Pressable>
          <View style={styles.dots}>
            {[1, 2, 3].map((n) => (
              <View key={n} style={[styles.stepDot, { backgroundColor: n <= stepNo ? c.tint : c.fillStrong, width: n === stepNo ? 22 : 8 }]} />
            ))}
          </View>
          <View style={{ minWidth: 70, alignItems: 'flex-end' }}>
            <T v="footnote" color={c.secondaryLabel} rounded>
              {stepNo} of 3
            </T>
          </View>
        </View>

        <Animated.View style={[styles.stage, { opacity: enter, transform: [{ translateY }] }]}>
          <View style={[styles.art, step === 'verify' && styles.artSmall]}>
            {placing ? (
              <Illustration name="calib-place" width={276} height={276}>
                <PlaceIllustration progress={place.progress} still={place.progress > 0} success={step === 'placed'} reduceMotion={reduceMotion} />
              </Illustration>
            ) : (
              <Illustration name="calib-point-left" width={300} height={300}>
                <PointIllustration active={step === 'point' ? target : undefined} ticked={ticked} reduceMotion={reduceMotion} />
              </Illustration>
            )}
          </View>

          <View style={styles.copy}>
            <T v="title" center>
              {title}
            </T>
            <T v="body" color={c.secondaryLabel} center style={{ maxWidth: 330 }}>
              {body}
            </T>
          </View>

          {step === 'place' ? (
            <View style={styles.status}>
              {p.gyroAvailable === false ? (
                <T v="subhead" color={c.errorText} center>
                  Motion sensors aren’t available on this device.
                </T>
              ) : (
                <View style={[styles.statusChip, { backgroundColor: c.fill }]}>
                  <Icon name={place.progress > 0 ? 'hand.raised.fill' : 'iphone.gen3'} size={16} color={place.progress > 0 ? c.tint : c.secondaryLabel} />
                  <T v="subhead" weight="600" color={place.progress > 0 ? c.label : c.secondaryLabel} rounded={place.progress > 0}>
                    {placeChip}
                  </T>
                </View>
              )}
            </View>
          ) : null}

          {step === 'point' ? (
            <View style={styles.status}>
              <View style={styles.progressDots} accessibilityLabel={`Dot ${targetIdx + 1} of ${CALIB_TARGETS.length}`}>
                {CALIB_TARGETS.map((t, i) => (
                  <View key={t} style={[styles.progressDot, { backgroundColor: i < targetIdx ? c.success : i === targetIdx ? c.tint : c.fillStrong }]} />
                ))}
              </View>
              <View style={[styles.statusChip, { backgroundColor: c.fill }]}>
                <Icon name="hand.tap.fill" size={16} color={c.tint} />
                <T v="subhead" weight="600">
                  {`${TARGET_NAMES[target]} · ${targetIdx + 1} of ${CALIB_TARGETS.length}`}
                </T>
              </View>
            </View>
          ) : null}

          {step === 'retry' && retry ? (
            <View style={styles.status}>
              <View style={[styles.statusChip, { backgroundColor: 'rgba(255,159,10,0.16)' }]}>
                <Icon name="exclamationmark.triangle.fill" size={16} color={c.warning} />
                <T v="subhead" weight="600" rounded>
                  {`Measured: ${Math.round(retry.degreesX)}° across · ${Math.round(retry.degreesY)}° up-down`}
                </T>
              </View>
            </View>
          ) : null}

          {step === 'verify' && speed ? (
            <Card style={[styles.verify, { backgroundColor: c.dark ? c.card : c.grouped }]} padded={false}>
              <View style={styles.checks}>
                {CALIB_TARGETS.map((t) => {
                  const ok = hits.includes(t);
                  return (
                    <View key={t} style={[styles.check, { backgroundColor: ok ? 'rgba(48,209,88,0.16)' : c.fill }]}>
                      <Icon name={ok ? 'checkmark.circle.fill' : 'circle'} size={15} color={ok ? c.success : c.secondaryLabel} />
                      <T v="footnote" weight="600" color={ok ? c.label : c.secondaryLabel}>
                        {TARGET_NAMES[t]}
                      </T>
                    </View>
                  );
                })}
              </View>
              <SliderRow
                title="Speed"
                value={speed.sensitivity}
                min={SENS_MIN}
                max={SENS_MAX}
                step={50}
                format={(v) => `${Math.round(v)}`}
                minIcon="tortoise.fill"
                maxIcon="hare.fill"
                onLive={(v) => !preview && verifyRef.current?.(verifyMotion(scaleSpeed(speed, v)))}
                onCommit={(v) => setSpeed(scaleSpeed(speed, v))}
              />
            </Card>
          ) : null}
        </Animated.View>

        <View style={styles.footer}>
          {!p.connected && step !== 'verify' ? (
            <View style={styles.offline}>
              <Icon name="laptopcomputer.slash" size={16} color={c.secondaryLabel} />
              <T v="footnote" color={c.secondaryLabel}>
                Connect to a Mac to see the guide on screen
              </T>
            </View>
          ) : null}
          {step === 'retry' ? <PrimaryButton title="Retry" icon="arrow.counterclockwise" onPress={toCenter} /> : null}
          {step === 'verify' ? (
            <View style={styles.buttons}>
              <SecondaryButton title="Redo" icon="arrow.counterclockwise" onPress={toCenter} style={styles.flex} />
              <PrimaryButton title="Done" onPress={done} style={styles.flex} />
            </View>
          ) : null}
        </View>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, paddingHorizontal: space.margin },
  header: { height: 44, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  dots: { flexDirection: 'row', gap: 6, alignItems: 'center' },
  stepDot: { height: 8, borderRadius: 4 },
  stage: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: space.xxl },
  art: { height: 300, alignItems: 'center', justifyContent: 'center' },
  copy: { gap: space.sm, alignItems: 'center', paddingHorizontal: space.sm },
  status: { minHeight: 40, alignItems: 'center', justifyContent: 'center' },
  statusChip: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 16, height: 40, borderRadius: 20 },
  artSmall: { height: 210, transform: [{ scale: 0.72 }] },
  progressDots: { flexDirection: 'row', gap: 8, marginBottom: space.sm, justifyContent: 'center' },
  progressDot: { width: 10, height: 10, borderRadius: 5 },
  verify: { alignSelf: 'stretch', paddingTop: space.md },
  checks: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, justifyContent: 'center', paddingHorizontal: space.md },
  check: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 10, height: 30, borderRadius: 15 },
  buttons: { flexDirection: 'row', gap: space.md },
  flex: { flex: 1 },
  footer: { gap: space.md, minHeight: 54, justifyContent: 'flex-end' },
  offline: { flexDirection: 'row', gap: 6, alignItems: 'center', justifyContent: 'center' },
});
