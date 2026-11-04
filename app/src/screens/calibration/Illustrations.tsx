import { useEffect } from 'react';
import { Animated, Easing, StyleSheet, View, useAnimatedValue } from 'react-native';
import Svg, { Circle, Defs, G, LinearGradient as SvgGradient, Rect, Stop } from 'react-native-svg';
import { Icon } from '../../ui/components';
import { glow } from '../../ui/tokens';
import { CALIB_TARGETS, targetFraction } from '../../motion/calibration';
import type { CalibTarget } from '../../transport/types';

const AnimatedCircle = Animated.createAnimatedComponent(Circle);

const SCREEN_BG = '#070B16';
const BEZEL = '#1A1F2B';

// Mini display (monitor) drawn in SVG, always dark like a real screen.
function Monitor(p: { w: number; h: number; children?: React.ReactNode }) {
  return (
    <View style={{ width: p.w, height: p.h + 22, alignItems: 'center' }}>
      <View style={[styles.monitor, { width: p.w, height: p.h }]}>
        <Svg width={p.w} height={p.h} style={StyleSheet.absoluteFill}>
          <Defs>
            <SvgGradient id="sky" x1="0" y1="0" x2="1" y2="1">
              <Stop offset="0" stopColor="#0B1430" />
              <Stop offset="1" stopColor={SCREEN_BG} />
            </SvgGradient>
          </Defs>
          <Rect x={4} y={4} width={p.w - 8} height={p.h - 8} rx={7} fill="url(#sky)" />
        </Svg>
        <Particles w={p.w} h={p.h} />
        {p.children}
      </View>
      <View style={styles.neck} />
      <View style={styles.foot} />
    </View>
  );
}

// A few slow cyan specks drifting across the mini display.
function Particles({ w, h }: { w: number; h: number }) {
  const t = useAnimatedValue(0);
  useEffect(() => {
    const loop = Animated.loop(Animated.timing(t, { toValue: 1, duration: 9000, easing: Easing.linear, useNativeDriver: true }));
    loop.start();
    return () => loop.stop();
  }, [t]);
  const dots = [
    { x: 0.12, y: 0.22, r: 1.6, dx: 18 },
    { x: 0.78, y: 0.18, r: 1.2, dx: -14 },
    { x: 0.3, y: 0.78, r: 1.4, dx: 12 },
    { x: 0.88, y: 0.66, r: 1.8, dx: -20 },
    { x: 0.55, y: 0.12, r: 1.0, dx: 10 },
    { x: 0.2, y: 0.5, r: 1.1, dx: -8 },
  ];
  return (
    <View style={StyleSheet.absoluteFill} pointerEvents="none">
      {dots.map((d, i) => (
        <Animated.View
          key={i}
          style={{
            position: 'absolute',
            left: d.x * w,
            top: d.y * h,
            width: d.r * 2,
            height: d.r * 2,
            borderRadius: d.r,
            backgroundColor: glow.core,
            opacity: t.interpolate({ inputRange: [0, 0.5, 1], outputRange: [0.25, 0.7, 0.25] }),
            transform: [{ translateX: t.interpolate({ inputRange: [0, 1], outputRange: [0, d.dx] }) }],
          }}
        />
      ))}
    </View>
  );
}

// Glowing cyan phone outline (layered strokes fake a bloom).
function GlowOutline(p: { w: number; h: number; color?: string }) {
  const color = p.color ?? glow.core;
  const pad = 8;
  const r = p.w * 0.2;
  return (
    <Svg width={p.w + pad * 2} height={p.h + pad * 2}>
      <Rect x={pad} y={pad} width={p.w} height={p.h} rx={r} fill="none" stroke={glow.outer} strokeOpacity={0.18} strokeWidth={12} />
      <Rect x={pad} y={pad} width={p.w} height={p.h} rx={r} fill="none" stroke={color} strokeOpacity={0.35} strokeWidth={6} />
      <Rect x={pad} y={pad} width={p.w} height={p.h} rx={r} fill={color} fillOpacity={0.06} stroke={color} strokeWidth={2} />
    </Svg>
  );
}

// iPhone, screen facing the viewer.
export function PhoneArt(p: { w: number; h: number; tilt?: boolean }) {
  const r = p.w * 0.2;
  return (
    <Svg width={p.w} height={p.h}>
      <Defs>
        <SvgGradient id="phoneScreen" x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor="#0A84FF" />
          <Stop offset="0.5" stopColor="#5E5CE6" />
          <Stop offset="1" stopColor="#BF5AF2" />
        </SvgGradient>
      </Defs>
      <Rect x={0} y={0} width={p.w} height={p.h} rx={r} fill="#E5E5EA" />
      <Rect x={1.5} y={1.5} width={p.w - 3} height={p.h - 3} rx={r - 1.5} fill="#1C1C1E" />
      <Rect x={3.5} y={3.5} width={p.w - 7} height={p.h - 7} rx={r - 3.5} fill="url(#phoneScreen)" />
      <Rect x={p.w / 2 - p.w * 0.16} y={p.h * 0.05} width={p.w * 0.32} height={p.h * 0.045} rx={p.h * 0.0225} fill="#000" />
    </Svg>
  );
}

// ---------- Step 1: hold to the screen ----------

const RING = 276;
const STROKE = 7;

export function PlaceIllustration(p: { progress: number; still: boolean; success: boolean; reduceMotion: boolean }) {
  const slide = useAnimatedValue(0); // 0 = below, 1 = settled
  const fade = useAnimatedValue(0);
  const breathe = useAnimatedValue(0);
  const prog = useAnimatedValue(0);
  const pop = useAnimatedValue(0);

  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(breathe, { toValue: 1, duration: 1400, easing: Easing.inOut(Easing.sin), useNativeDriver: true }),
        Animated.timing(breathe, { toValue: 0, duration: 1400, easing: Easing.inOut(Easing.sin), useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [breathe]);

  // Phone slides up into the outline and settles, then fades and repeats.
  // While the user is holding still (progress > 0) the phone stays parked.
  const holding = p.progress > 0 || p.success;
  useEffect(() => {
    if (holding) {
      Animated.parallel([
        Animated.spring(slide, { toValue: 1, useNativeDriver: true, damping: 16, stiffness: 140 }),
        Animated.timing(fade, { toValue: 1, duration: 200, useNativeDriver: true }),
      ]).start();
      return;
    }
    slide.setValue(p.reduceMotion ? 1 : 0);
    fade.setValue(0);
    const loop = Animated.loop(
      Animated.sequence([
        Animated.delay(400),
        Animated.parallel([
          p.reduceMotion ? Animated.delay(0) : Animated.spring(slide, { toValue: 1, useNativeDriver: true, damping: 14, stiffness: 110 }),
          Animated.timing(fade, { toValue: 1, duration: 350, useNativeDriver: true }),
        ]),
        Animated.delay(1500),
        Animated.timing(fade, { toValue: 0, duration: 450, useNativeDriver: true }),
        Animated.timing(slide, { toValue: p.reduceMotion ? 1 : 0, duration: 0, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [holding, p.reduceMotion, slide, fade]);

  useEffect(() => {
    Animated.timing(prog, { toValue: p.success ? 1 : p.progress, duration: p.progress === 0 ? 350 : 120, easing: Easing.linear, useNativeDriver: false }).start();
  }, [p.progress, p.success, prog]);

  useEffect(() => {
    if (p.success) Animated.spring(pop, { toValue: 1, useNativeDriver: true, damping: 11, stiffness: 220 }).start();
    else pop.setValue(0);
  }, [p.success, pop]);

  const rr = (RING - STROKE) / 2;
  const circ = 2 * Math.PI * rr;
  const monitorW = 196;
  const monitorH = 124;
  const phoneW = 30;
  const phoneH = 61;

  return (
    <View style={{ width: RING, height: RING, alignItems: 'center', justifyContent: 'center' }}>
      <Svg width={RING} height={RING} style={StyleSheet.absoluteFill}>
        <Defs>
          <SvgGradient id="ring" x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0" stopColor={glow.core} />
            <Stop offset="1" stopColor={glow.outer} />
          </SvgGradient>
        </Defs>
        <Circle cx={RING / 2} cy={RING / 2} r={rr} stroke="rgba(127,127,140,0.22)" strokeWidth={STROKE} fill="none" />
        <G rotation={-90} origin={`${RING / 2}, ${RING / 2}`}>
          <AnimatedCircle
            cx={RING / 2}
            cy={RING / 2}
            r={rr}
            stroke={p.success ? '#30D158' : 'url(#ring)'}
            strokeWidth={STROKE}
            strokeLinecap="round"
            fill="none"
            strokeDasharray={`${circ} ${circ}`}
            strokeDashoffset={prog.interpolate({ inputRange: [0, 1], outputRange: [circ, 0] })}
          />
        </G>
      </Svg>
      <Monitor w={monitorW} h={monitorH}>
        <View style={styles.centerFill}>
          <Animated.View style={{ opacity: breathe.interpolate({ inputRange: [0, 1], outputRange: [0.65, 1] }) }}>
            <GlowOutline w={phoneW} h={phoneH} color={p.success ? '#30D158' : undefined} />
          </Animated.View>
        </View>
      </Monitor>
      <Animated.View
        pointerEvents="none"
        style={[
          styles.phoneLayer,
          {
            opacity: fade,
            transform: [{ translateY: slide.interpolate({ inputRange: [0, 1], outputRange: [150, 0] }) }, { scale: slide.interpolate({ inputRange: [0, 1], outputRange: [1.25, 1] }) }],
          },
        ]}
      >
        <View style={{ marginBottom: 22 }}>
          <PhoneArt w={phoneW} h={phoneH} />
        </View>
      </Animated.View>
      <Animated.View style={[styles.tick, { opacity: pop, transform: [{ scale: pop.interpolate({ inputRange: [0, 1], outputRange: [0.4, 1] }) }] }]}>
        <Icon name="checkmark.circle.fill" size={54} color="#30D158" />
      </Animated.View>
    </View>
  );
}

// ---------- Step 2/3: point at the 5 dots (centre + corners) ----------

const ILL_W = 300;
const ILL_H = 300;
const MON_W = 264;
const MON_H = 150;

// `active` = the dot to point at now (phone turns toward it); `ticked` = done
// dots (green tick). Without `active` (verify step) the phone stays upright.
export function PointIllustration(p: { active?: CalibTarget; ticked: readonly CalibTarget[]; reduceMotion: boolean }) {
  const pulse = useAnimatedValue(0);
  const turn = useAnimatedValue(0);

  useEffect(() => {
    const loop = Animated.loop(Animated.timing(pulse, { toValue: 1, duration: 1500, easing: Easing.out(Easing.quad), useNativeDriver: true }));
    loop.start();
    return () => loop.stop();
  }, [pulse]);

  useEffect(() => {
    turn.setValue(0);
    if (!p.active) return;
    if (p.reduceMotion) {
      turn.setValue(1);
      return;
    }
    Animated.spring(turn, { toValue: 1, useNativeDriver: true, damping: 14, stiffness: 90 }).start();
  }, [p.active, p.reduceMotion, turn]);

  const monLeft = (ILL_W - MON_W) / 2;
  const pos = (t: CalibTarget) => {
    const f = targetFraction(t);
    return { x: monLeft + f.x * MON_W, y: f.y * MON_H };
  };
  const phoneW = 34;
  const phoneH = 70;
  const pivotX = ILL_W / 2;
  const pivotY = ILL_H - 6;
  const aim = pos(p.active ?? 'center');
  const angle = p.active ? (Math.atan2(aim.x - pivotX, pivotY - aim.y) * 180) / Math.PI : 0;
  const beamLen = Math.hypot(aim.x - pivotX, pivotY - aim.y) - phoneH - 4;
  const rotate = turn.interpolate({ inputRange: [0, 1], outputRange: ['0deg', `${angle}deg`] });

  return (
    <View style={{ width: ILL_W, height: ILL_H }}>
      <View style={{ position: 'absolute', left: monLeft, top: 0 }}>
        <Monitor w={MON_W} h={MON_H} />
      </View>
      {CALIB_TARGETS.map((t) => {
        const d = pos(t);
        return p.ticked.includes(t) ? (
          <View key={t} style={[styles.dotWrap, { left: d.x - 22, top: d.y - 22 }]}>
            <View style={styles.hitRing} />
            <Icon name="checkmark" size={12} color="#FFFFFF" weight="bold" style={{ position: 'absolute' }} />
          </View>
        ) : (
          <TargetDot key={t} x={d.x} y={d.y} active={t === p.active || !p.active} pulse={pulse} />
        );
      })}

      <Animated.View
        style={{
          position: 'absolute',
          left: pivotX - phoneW / 2,
          top: pivotY - phoneH - beamLen - 4,
          width: phoneW,
          height: phoneH + beamLen + 4,
          alignItems: 'center',
          transformOrigin: 'bottom',
          transform: [{ rotate }],
        }}
      >
        <Animated.View style={{ height: beamLen, width: 3, opacity: p.active ? turn.interpolate({ inputRange: [0, 0.6, 1], outputRange: [0.15, 0.4, 1] }) : 0 }}>
          <Svg width={3} height={beamLen}>
            <Defs>
              <SvgGradient id="beam" x1="0" y1="1" x2="0" y2="0">
                <Stop offset="0" stopColor={glow.core} stopOpacity={0.05} />
                <Stop offset="1" stopColor={glow.core} stopOpacity={0.95} />
              </SvgGradient>
            </Defs>
            <Rect x={0} y={0} width={3} height={beamLen} rx={1.5} fill="url(#beam)" />
          </Svg>
        </Animated.View>
        <View style={{ height: 4 }} />
        <PhoneArt w={phoneW} h={phoneH} />
      </Animated.View>
    </View>
  );
}

function TargetDot(p: { x: number; y: number; active: boolean; pulse: Animated.Value }) {
  return (
    <View style={[styles.dotWrap, { left: p.x - 22, top: p.y - 22 }]}>
      {p.active ? (
        <Animated.View
          style={[
            styles.dotPulse,
            {
              opacity: p.pulse.interpolate({ inputRange: [0, 1], outputRange: [0.7, 0] }),
              transform: [{ scale: p.pulse.interpolate({ inputRange: [0, 1], outputRange: [0.5, 1.6] }) }],
            },
          ]}
        />
      ) : null}
      <View style={[styles.dot, { backgroundColor: p.active ? glow.core : 'rgba(100,210,255,0.25)' }]} />
    </View>
  );
}

const styles = StyleSheet.create({
  monitor: { backgroundColor: BEZEL, borderRadius: 11, overflow: 'hidden', borderWidth: 1, borderColor: '#2A3040' },
  neck: { width: 26, height: 14, backgroundColor: '#3A3F4B' },
  foot: { width: 74, height: 6, borderRadius: 3, backgroundColor: '#4A505C' },
  centerFill: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center' },
  phoneLayer: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center' },
  tick: { position: 'absolute', bottom: 18, alignSelf: 'center', backgroundColor: '#FFFFFF', borderRadius: 30 },
  dotWrap: { position: 'absolute', width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  dotPulse: { position: 'absolute', width: 44, height: 44, borderRadius: 22, backgroundColor: glow.core },
  dot: { width: 14, height: 14, borderRadius: 7, shadowColor: glow.core, shadowOpacity: 0.9, shadowRadius: 8, shadowOffset: { width: 0, height: 0 } },
  hitRing: { width: 22, height: 22, borderRadius: 11, backgroundColor: '#30D158', borderWidth: 2, borderColor: 'rgba(255,255,255,0.9)' },
});
