import { useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { DeviceMotion } from 'expo-sensors';
import Svg, { G, Path, Polygon, Rect, Text as SvgText } from 'react-native-svg';
import { AirMouseMotionView } from '../../modules/airmouse-discovery';
import { SecondaryButton, T } from './components';
import { autoPose, stepCursor } from './sensorToCursor';
import { radius, space, type Palette } from './tokens';

// Curved arrow along an ellipse. Angles in degrees, increasing = clockwise on screen.
export function CurveArrow({ cx, cy, rx, ry, a0, a1, color, opacity = 1, width = 3.5 }: { cx: number; cy: number; rx: number; ry: number; a0: number; a1: number; color: string; opacity?: number; width?: number }) {
  const rad = (d: number) => (d * Math.PI) / 180;
  const pt = (a: number) => [cx + rx * Math.cos(rad(a)), cy + ry * Math.sin(rad(a))];
  const [x0, y0] = pt(a0);
  const [x1, y1] = pt(a1);
  const sign = a1 > a0 ? 1 : -1;
  const large = Math.abs(a1 - a0) > 180 ? 1 : 0;
  let tx = -sign * rx * Math.sin(rad(a1));
  let ty = sign * ry * Math.cos(rad(a1));
  const len = Math.hypot(tx, ty) || 1;
  tx /= len; ty /= len;
  const nx = -ty; const ny = tx;
  const head = `${x1 + tx * 8},${y1 + ty * 8} ${x1 - tx * 3 + nx * 6},${y1 - ty * 3 + ny * 6} ${x1 - tx * 3 - nx * 6},${y1 - ty * 3 - ny * 6}`;
  return <G opacity={opacity}>
    <Path d={`M ${x0} ${y0} A ${rx} ${ry} 0 ${large} ${sign > 0 ? 1 : 0} ${x1} ${y1}`} stroke={color} strokeWidth={width} strokeLinecap="round" fill="none" />
    <Polygon points={head} fill={color} />
  </G>;
}

type Mode = 'auto' | 'live';
type Pose = { yaw: number; pitch: number; roll: number }; // radians
const REST: Pose = { yaw: 0, pitch: 0, roll: 0 };
const RAD = Math.PI / 180;
const MAC_W = 124; const MAC_H = 78; const DOT = 14;
const HIGHLIGHTS = ['yaw', 'pitch', 'roll'] as const;

// 2D labelled fallback for builds without the native SceneKit view.
function Flat({ w, c, pose, phase }: { w: number; c: Palette; pose: Pose; phase: number }) {
  const op = (i: number) => (phase < 0 || phase === i ? 1 : 0.3);
  return <Svg width={w} height={w * 0.56} viewBox="0 0 320 180">
    <G translateX={pose.yaw * 90} translateY={-pose.pitch * 90} rotation={pose.roll / RAD} origin="160,95">
      <Rect x={133} y={45} width={54} height={104} rx={11} fill={c.dark ? '#2C2C2E' : '#E5E5EA'} stroke={c.label} strokeOpacity={0.7} strokeWidth={2.5} />
      <Rect x={139} y={54} width={42} height={86} rx={6} fill={c.tint} fillOpacity={0.2} />
    </G>
    <CurveArrow cx={160} cy={36} rx={70} ry={14} a0={205} a1={335} color={c.axisZ} opacity={op(0)} />
    <CurveArrow cx={235} cy={95} rx={14} ry={56} a0={-65} a1={65} color={c.axisY} opacity={op(1)} />
    <CurveArrow cx={160} cy={95} rx={88} ry={88} a0={150} a1={205} color={c.secondaryLabel} opacity={0.6} width={3} />
    <SvgText x={160} y={14} fontSize={11} fontWeight="700" fill={c.axisZ} textAnchor="middle">{'yaw'}</SvgText>
    <SvgText x={256} y={99} fontSize={11} fontWeight="700" fill={c.axisY}>{'pitch'}</SvgText>
    <SvgText x={14} y={99} fontSize={11} fontWeight="700" fill={c.secondaryLabel}>{'roll'}</SvgText>
  </Svg>;
}

/** Real 3D phone (SceneKit) with yaw/pitch/roll rings, beside a mini Mac screen whose cursor follows the same maths as engine.ts. */
export function MotionDemo3D({ w, c, reduce }: { w: number; c: Palette; reduce: boolean }) {
  const [mode, setMode] = useState<Mode>('auto');
  const [avail, setAvail] = useState(false);
  const [phase, setPhase] = useState(-1);
  const [pose, setPose] = useState<Pose>(REST);
  const [cursor, setCursor] = useState({ x: 0, y: 0 });
  const ref0 = useRef<{ a: number; b: number; g: number } | null>(null);
  const cursorRef = useRef({ x: 0, y: 0 });
  const lastT = useRef(0);

  useEffect(() => {
    let alive = true;
    DeviceMotion.isAvailableAsync().then((ok) => { if (alive && ok) { setAvail(true); setMode('live'); } }).catch(() => {});
    return () => { alive = false; };
  }, []);

  // Live: real orientation drives the model, real gyro rate drives the cursor.
  useEffect(() => {
    if (mode !== 'live') return;
    ref0.current = null;
    cursorRef.current = { x: 0, y: 0 };
    lastT.current = 0;
    DeviceMotion.setUpdateInterval(33);
    const sub = DeviceMotion.addListener((e) => {
      const r = e.rotation;
      const rate = e.rotationRate;
      const now = Date.now();
      if (r) {
        if (!ref0.current) ref0.current = { a: r.alpha, b: r.beta, g: r.gamma };
        const o = ref0.current;
        const da = Math.atan2(Math.sin(r.alpha - o.a), Math.cos(r.alpha - o.a));
        setPose({ yaw: -da, pitch: r.beta - o.b, roll: r.gamma - o.g });
      }
      if (rate) {
        const dt = lastT.current ? Math.min(0.1, (now - lastT.current) / 1000) : 0;
        cursorRef.current = stepCursor(cursorRef.current, rate.beta * RAD, rate.alpha * RAD, dt);
        setCursor(cursorRef.current);
      }
      lastT.current = now;
    });
    return () => sub.remove();
  }, [mode]);

  // Auto: scripted yaw, pitch, roll loop. Reduce Motion freezes it on a still pose.
  useEffect(() => {
    if (mode !== 'auto' || reduce) return;
    const start = Date.now();
    const id = setInterval(() => {
      const p = autoPose((Date.now() - start) / 1000);
      setPose({ yaw: p.yaw * RAD, pitch: p.pitch * RAD, roll: p.roll * RAD });
      setPhase(p.phase);
      setCursor({ x: p.cx, y: p.cy });
    }, 33);
    return () => clearInterval(id);
  }, [mode, reduce]);

  const pick = (m: Mode) => {
    if (m === mode) return;
    setPose(REST); setCursor({ x: 0, y: 0 }); setPhase(-1);
    setMode(m);
  };
  const recenter = () => { ref0.current = null; cursorRef.current = { x: 0, y: 0 }; setCursor({ x: 0, y: 0 }); setPose(REST); };

  const active = (i: number) => mode === 'live' || phase === i || phase < 0;
  const legend: [string, string, number, boolean][] = [
    [c.axisZ, 'Turn left/right: cursor moves sideways', 0, false],
    [c.axisY, 'Tilt up/down: cursor moves up/down', 1, false],
    [c.secondaryLabel, 'Twist: ignored', 2, true],
  ];
  const hl = mode === 'auto' && phase >= 0 ? HIGHLIGHTS[phase] : null;

  return <View style={[styles.panel, { width: w, backgroundColor: c.card, borderColor: c.separator }]}>
    {AirMouseMotionView
      ? <AirMouseMotionView style={{ width: '100%', height: 230 }} yaw={pose.yaw} pitch={pose.pitch} roll={pose.roll} highlight={hl} dark={c.dark} />
      : <Flat w={w - space.lg * 2} c={c} pose={pose} phase={phase} />}
    <View style={styles.row}>
      <View style={styles.legend}>
        {legend.map(([color, text, i, struck]) => <View key={text} style={styles.legendRow}>
          <View style={[styles.swatch, { backgroundColor: color, opacity: active(i) ? 1 : 0.4 }]} />
          <T v="footnote" weight={mode === 'auto' && phase === i ? '700' : '500'} color={struck ? c.secondaryLabel : c.label} style={[styles.legendText, struck ? styles.strike : null]}>{text}</T>
        </View>)}
      </View>
      <View style={styles.macCol}>
        <View style={[styles.mac, { backgroundColor: c.fill, borderColor: c.label }]} accessibilityLabel="Mac screen">
          <View style={[styles.cursor, { left: ((cursor.x + 1) / 2) * (MAC_W - 4 - DOT), top: ((cursor.y + 1) / 2) * (MAC_H - 4 - DOT), backgroundColor: c.tint }]} />
        </View>
        <View style={[styles.stand, { backgroundColor: c.label }]} />
        <T v="caption" weight="600" color={c.secondaryLabel}>Mac screen</T>
      </View>
    </View>
    <View style={styles.controls}>
      <View style={[styles.seg, { backgroundColor: c.fillStrong }]}>
        <Pressable disabled={!avail} onPress={() => pick('live')} style={[styles.segBtn, mode === 'live' && { backgroundColor: c.tint }, !avail && { opacity: 0.4 }]} accessibilityRole="button"><T v="footnote" weight="600" color={mode === 'live' ? c.onTint : c.label}>Live</T></Pressable>
        <Pressable onPress={() => pick('auto')} style={[styles.segBtn, mode === 'auto' && { backgroundColor: c.tint }]} accessibilityRole="button"><T v="footnote" weight="600" color={mode === 'auto' ? c.onTint : c.label}>Demo</T></Pressable>
      </View>
      {mode === 'live' ? <SecondaryButton title="Recenter" icon="scope" onPress={recenter} plain /> : <View />}
    </View>
    <T v="caption" color={c.secondaryLabel} center>{mode === 'live' ? 'Turn your iPhone and watch the model and the cursor follow. Drag the 3D view to look around.' : 'Drag the 3D view to look around.'}</T>
  </View>;
}

const styles = StyleSheet.create({
  panel: { borderRadius: radius.card + 2, borderWidth: 1, padding: space.lg, gap: space.md },
  row: { flexDirection: 'row', alignItems: 'center', gap: space.md },
  legend: { flex: 1, gap: 8 },
  legendRow: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  legendText: { flex: 1 },
  swatch: { width: 12, height: 12, borderRadius: 6 },
  strike: { textDecorationLine: 'line-through' },
  macCol: { width: MAC_W, alignItems: 'center', gap: 5 },
  mac: { width: MAC_W, height: MAC_H, borderWidth: 2, borderRadius: 6, overflow: 'hidden' },
  cursor: { position: 'absolute', width: DOT, height: DOT, borderRadius: DOT / 2 },
  stand: { width: 28, height: 3, borderRadius: 1.5, opacity: 0.6 },
  controls: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  seg: { flexDirection: 'row', borderRadius: 9, padding: 2 },
  segBtn: { paddingHorizontal: 14, paddingVertical: 5, borderRadius: 7 },
});
