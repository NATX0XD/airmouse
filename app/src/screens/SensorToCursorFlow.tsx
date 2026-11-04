import { useEffect, useState, type ReactNode } from 'react';
import { Animated, Modal, PanResponder, Pressable, ScrollView, StyleSheet, View, useAnimatedValue, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Svg, { Circle, G, Line, Path, Polygon, Polyline, Rect, Text as SvgText } from 'react-native-svg';
import { Icon, PrimaryButton, T, type SymbolName } from '../ui/components';
import { burstPos, dotsMoved, EXAMPLE_DEG_PER_SEC, EXAMPLE_DOTS_PER_DEG, rawLine, smoothLine } from '../ui/sensorToCursor';
import { radius, space, usePalette, useReduceMotion, type Palette } from '../ui/tokens';

type Props = { visible: boolean; onDone: () => void };
type DiagramProps = { w: number; c: Palette; reduce: boolean };
type Step = { title: string; body: string; extra?: string; Diagram: (p: DiagramProps) => ReactNode };

// Animation clock. Re-renders ~25x/s while mounted; frozen at `still` when Reduce Motion is on.
function useClock(reduce: boolean, still: number): number {
  const [t, setT] = useState(0);
  useEffect(() => {
    if (reduce) return;
    const start = Date.now();
    const id = setInterval(() => setT((Date.now() - start) / 1000), 40);
    return () => clearInterval(id);
  }, [reduce]);
  return reduce ? still : t;
}

const VB_W = 320;
const VB_H = 200;
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

function Canvas({ w, c, children }: { w: number; c: Palette; children: ReactNode }) {
  return <Svg width={w} height={(w * VB_H) / VB_W} viewBox={`0 0 ${VB_W} ${VB_H}`}>
    <Rect x={1} y={1} width={VB_W - 2} height={VB_H - 2} rx={24} fill={c.card} stroke={c.separator} strokeWidth={1} />
    {children}
  </Svg>;
}

function Phone({ c, x, y, w = 54, h = 104, screenTint }: { c: Palette; x: number; y: number; w?: number; h?: number; screenTint?: string }) {
  return <G>
    <Rect x={x - w / 2} y={y - h / 2} width={w} height={h} rx={w * 0.2} fill={c.dark ? '#2C2C2E' : '#E5E5EA'} stroke={c.label} strokeOpacity={0.7} strokeWidth={2.5} />
    <Rect x={x - w / 2 + 5} y={y - h / 2 + 9} width={w - 10} height={h - 18} rx={w * 0.12} fill={screenTint ?? c.tint} fillOpacity={0.16} />
    <Rect x={x - 8} y={y - h / 2 + 3.5} width={16} height={3} rx={1.5} fill={c.label} fillOpacity={0.5} />
  </G>;
}

// Curved arrow along an ellipse. Angles in degrees, increasing = clockwise on screen.
function CurveArrow({ cx, cy, rx, ry, a0, a1, color, opacity = 1, width = 3.5 }: { cx: number; cy: number; rx: number; ry: number; a0: number; a1: number; color: string; opacity?: number; width?: number }) {
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

// ---------- 1. Gyroscope measures turning speed ----------
function GyroDiagram({ w, c, reduce }: DiagramProps) {
  const t = useClock(reduce, 0.6);
  const tilt = Math.sin(t * 1.6) * 9;
  const sample = Math.floor(t * 100);
  const pulse = (t * 100) % 1;
  return <Canvas w={w} c={c}>
    <G rotation={tilt} origin="160,100"><Phone c={c} x={160} y={100} /></G>
    <CurveArrow cx={160} cy={46} rx={74} ry={16} a0={205} a1={335} color={c.axisZ} />
    <CurveArrow cx={238} cy={100} rx={16} ry={66} a0={-65} a1={65} color={c.axisY} />
    <CurveArrow cx={160} cy={100} rx={92} ry={92} a0={150} a1={210} color={c.axisX} />
    <SvgText x={160} y={14} fontSize={11} fontWeight="700" fill={c.axisZ} textAnchor="middle">{'yaw: turn left/right'}</SvgText>
    <SvgText x={262} y={104} fontSize={11} fontWeight="700" fill={c.axisY}>{'pitch'}</SvgText>
    <SvgText x={12} y={104} fontSize={11} fontWeight="700" fill={c.axisX}>{'roll'}</SvgText>
    <Circle cx={36} cy={176} r={4 + pulse * 3} fill={c.tint} fillOpacity={1 - pulse * 0.6} />
    <SvgText x={46} y={180} fontSize={11} fontWeight="600" fill={c.label}>{`every 10 ms  ·  sample ${sample}`}</SvgText>
  </Canvas>;
}

// ---------- 2. Three directions ----------
function AxesDiagram({ w, c, reduce }: DiagramProps) {
  const t = useClock(reduce, 0.5);
  const phase = Math.floor((t / 2.2) % 3);
  const k = Math.sin(((t / 2.2) % 1) * Math.PI * 2);
  const dx = phase === 0 ? k * 10 : 0;
  const dy = phase === 1 ? k * 9 : 0;
  const roll = phase === 2 ? k * 14 : 0;
  const op = (i: number) => (phase === i ? 1 : 0.35);
  return <Canvas w={w} c={c}>
    <G translateX={dx} translateY={dy} rotation={roll} origin="96,100"><Phone c={c} x={96} y={100} w={46} h={90} /></G>
    <CurveArrow cx={96} cy={42} rx={52} ry={12} a0={205} a1={335} color={c.axisZ} opacity={op(0)} />
    <CurveArrow cx={150} cy={100} rx={11} ry={50} a0={-65} a1={65} color={c.axisY} opacity={op(1)} />
    <CurveArrow cx={96} cy={100} rx={74} ry={74} a0={150} a1={210} color={c.tertiaryLabel} opacity={0.9} width={3} />
    <SvgText x={96} y={16} fontSize={11} fontWeight="700" fill={c.axisZ} textAnchor="middle" opacity={op(0)}>{'yaw: left/right'}</SvgText>
    <SvgText x={160} y={104} fontSize={11} fontWeight="700" fill={c.axisY} opacity={op(1)}>{'pitch'}</SvgText>
    <SvgText x={96} y={186} fontSize={11} fontWeight="700" fill={c.secondaryLabel} textAnchor="middle">{'roll: ignored'}</SvgText>
    <Rect x={190} y={36} width={112} height={128} rx={14} fill={c.fill} stroke={c.separator} />
    <Line x1={246} y1={44} x2={246} y2={156} stroke={c.separator} strokeDasharray="3 4" />
    <Line x1={198} y1={100} x2={294} y2={100} stroke={c.separator} strokeDasharray="3 4" />
    <Circle cx={246 + dx * 4.2} cy={100 + dy * 5} r={7} fill={c.tint} />
    <SvgText x={246} y={182} fontSize={11} fontWeight="600" fill={c.secondaryLabel} textAnchor="middle">{'cursor on Mac'}</SvgText>
  </Canvas>;
}

// ---------- 3. Removing the drift ----------
function DriftDiagram({ w, c, reduce }: DiagramProps) {
  const t = useClock(reduce, 2.6);
  const p = (t % 4) / 4;
  const panel = (x: number, drift: boolean) => {
    const cx = x + 66; const cy = 92;
    const ox = drift ? p * 38 : 0; const oy = drift ? p * -22 : 0;
    return <G key={x}>
      <Rect x={x} y={30} width={132} height={124} rx={16} fill={c.fill} stroke={c.separator} />
      <Line x1={cx - 50} y1={cy} x2={cx + 50} y2={cy} stroke={c.separator} strokeDasharray="3 4" />
      <Line x1={cx} y1={cy - 46} x2={cx} y2={cy + 46} stroke={c.separator} strokeDasharray="3 4" />
      {drift ? <Line x1={cx} y1={cy} x2={cx + ox} y2={cy + oy} stroke={c.warning} strokeWidth={2} strokeOpacity={0.7} /> : <Circle cx={cx} cy={cy} r={11 + Math.sin(t * 3) * 1.5} fill="none" stroke={c.success} strokeOpacity={0.5} strokeWidth={2} />}
      <Circle cx={cx + ox} cy={cy + oy} r={7} fill={drift ? c.warning : c.success} />
    </G>;
  };
  return <Canvas w={w} c={c}>
    {panel(16, true)}
    {panel(172, false)}
    <Path d="M 152 92 L 168 92" stroke={c.label} strokeOpacity={0.6} strokeWidth={2.5} strokeLinecap="round" />
    <Polygon points="170,92 163,87 163,97" fill={c.label} fillOpacity={0.6} />
    <SvgText x={82} y={176} fontSize={11} fontWeight="600" fill={c.label} textAnchor="middle">{'Creeps by itself'}</SvgText>
    <SvgText x={238} y={176} fontSize={11} fontWeight="600" fill={c.label} textAnchor="middle">{'After subtracting bias'}</SvgText>
    <SvgText x={160} y={20} fontSize={10.5} fontWeight="600" fill={c.secondaryLabel} textAnchor="middle">{'phone lying still'}</SvgText>
  </Canvas>;
}

// ---------- 4. Calming shaky hands ----------
function SmoothDiagram({ w, c, reduce }: DiagramProps) {
  const t = useClock(reduce, 1.2);
  const N = 70; const x0 = 22; const cw = 276; const h = 54;
  const line = (top: number, fn: (u: number) => number) => Array.from({ length: N + 1 }, (_, i) => { const u = i / N; return `${x0 + u * cw},${top + h - clamp(fn(u), 0, 1) * h}`; }).join(' ');
  const phase = t * 14;
  return <Canvas w={w} c={c}>
    <SvgText x={22} y={22} fontSize={11} fontWeight="600" fill={c.label}>{'Raw sensor'}</SvgText>
    <Polyline points={line(28, (u) => rawLine(u, 0.1, phase))} fill="none" stroke={c.warning} strokeWidth={2} strokeLinejoin="round" />
    <SvgText x={22} y={112} fontSize={11} fontWeight="600" fill={c.label}>{'After the One Euro filter'}</SvgText>
    <Polyline points={line(118, (u) => smoothLine(u, 0.1, phase))} fill="none" stroke={c.tint} strokeWidth={3} strokeLinejoin="round" strokeLinecap="round" />
    <SvgText x={298} y={106} fontSize={10} fill={c.secondaryLabel} textAnchor="end">{'quick flick passes through'}</SvgText>
  </Canvas>;
}

// ---------- 5. Speed x time = distance (RN views) ----------
function EquationDiagram({ w, c, reduce }: DiagramProps) {
  const t = useClock(reduce, 1.8);
  const p = clamp((t % 3.2) / 2.6, 0, 1);
  const elapsed = Math.round(p * 1000);
  const dots = Math.round(dotsMoved(EXAMPLE_DEG_PER_SEC, elapsed, EXAMPLE_DOTS_PER_DEG));
  const chip = (value: string, unit: string, color: string) => <View style={[styles.chip, { backgroundColor: c.fill, borderColor: color }]}><T v="title2" rounded color={color}>{value}</T><T v="caption" color={c.secondaryLabel}>{unit}</T></View>;
  const op = (s: string) => <T v="title2" color={c.secondaryLabel}>{s}</T>;
  return <View style={[styles.panel, { width: w, backgroundColor: c.card, borderColor: c.separator }]}>
    <T v="caption" color={c.secondaryLabel}>For one 10 ms sample</T>
    <View style={styles.eqRow}>{chip(String(EXAMPLE_DEG_PER_SEC), 'degrees/s', c.axisZ)}{op('×')}{chip('0.01', 'seconds', c.axisY)}{op('×')}{chip(String(EXAMPLE_DOTS_PER_DEG), 'dots/degree', c.axisX)}{op('≈')}{chip('7', 'dots', c.tint)}</View>
    <View style={[styles.rule, { backgroundColor: c.separator }]} />
    <T v="caption" color={c.secondaryLabel}>Keep turning for one second</T>
    <View style={styles.counterRow}><T v="largeTitle" rounded color={c.tint}>{String(dots)}</T><T v="callout" color={c.secondaryLabel}>dots</T><View style={{ flex: 1 }} /><T v="subhead" rounded color={c.secondaryLabel}>{`${elapsed} ms`}</T></View>
    <View style={[styles.track, { backgroundColor: c.fillStrong }]}><View style={[styles.fillBar, { width: `${p * 100}%`, backgroundColor: c.tint }]} /></View>
  </View>;
}

// ---------- 6. Calibration sets the scale ----------
const CALIB_DOTS: [number, number][] = [[52, 30], [268, 30], [160, 62], [52, 94], [268, 94]];
function CalibrationDiagram({ w, c, reduce }: DiagramProps) {
  const t = useClock(reduce, 0.5);
  const active = Math.floor(t / 1.1) % 5;
  const ph = (t / 1.1) % 1;
  return <Canvas w={w} c={c}>
    <Rect x={26} y={12} width={268} height={100} rx={12} fill={c.fill} stroke={c.separator} />
    {CALIB_DOTS.map(([x, y], i) => <Line key={`l${i}`} x1={160} y1={150} x2={x} y2={y} stroke={c.tint} strokeOpacity={i === active ? 0.8 : 0.14} strokeWidth={i === active ? 2 : 1.5} strokeDasharray={i === active ? undefined : '3 4'} />)}
    {CALIB_DOTS.map(([x, y], i) => <G key={`d${i}`}>
      {i === active ? <Circle cx={x} cy={y} r={7 + ph * 9} fill={c.tint} fillOpacity={0.3 * (1 - ph)} /> : null}
      <Circle cx={x} cy={y} r={i === active ? 7 : 5.5} fill={i === active ? c.tint : c.tertiaryLabel} />
    </G>)}
    <Phone c={c} x={160} y={160} w={28} h={50} />
    <SvgText x={298} y={186} fontSize={10.5} fontWeight="600" fill={c.secondaryLabel} textAnchor="end">{'dots per degree'}</SvgText>
    <SvgText x={22} y={186} fontSize={10.5} fontWeight="600" fill={c.secondaryLabel}>{`dot ${active + 1} of 5`}</SvgText>
  </Canvas>;
}

// ---------- 7. A tiny message to your Mac ----------
function MessageDiagram({ w, c, reduce }: DiagramProps) {
  const t = useClock(reduce, 0.45);
  const x0 = 64; const x1 = 244;
  const wifi = Array.from({ length: 6 }, (_, i) => ((t * 0.9 + i / 6) % 1));
  const bt = Array.from({ length: 2 }, (_, i) => ((t * 0.28 + i / 2) % 1));
  return <Canvas w={w} c={c}>
    <Rect x={70} y={14} width={180} height={26} rx={13} fill={c.tint} fillOpacity={c.dark ? 0.28 : 0.14} stroke={c.tint} strokeOpacity={0.5} />
    <SvgText x={160} y={31} fontSize={11.5} fontWeight="600" fill={c.label} textAnchor="middle">{'move 7.9 right, 0.4 up'}</SvgText>
    <Phone c={c} x={36} y={104} w={32} h={60} />
    <G>
      <Rect x={262} y={72} width={44} height={60} rx={5} fill={c.fill} stroke={c.label} strokeOpacity={0.6} strokeWidth={2} />
      <Rect x={256} y={134} width={56} height={5} rx={2.5} fill={c.label} fillOpacity={0.5} />
    </G>
    <Line x1={x0} y1={78} x2={x1} y2={78} stroke={c.separator} strokeDasharray="2 5" />
    <Line x1={x0} y1={130} x2={x1} y2={130} stroke={c.separator} strokeDasharray="2 5" />
    {wifi.map((u, i) => <Rect key={`w${i}`} x={x0 + u * (x1 - x0) - 7} y={73} width={14} height={9} rx={4.5} fill={c.tint} fillOpacity={0.9} />)}
    {bt.map((u, i) => <Rect key={`b${i}`} x={x0 + u * (x1 - x0) - 14} y={123} width={28} height={14} rx={7} fill={c.axisZ === c.tint ? c.warning : c.axisZ} fillOpacity={0.9} />)}
    <SvgText x={x0} y={66} fontSize={10.5} fontWeight="600" fill={c.label}>{'Wi-Fi · about 100 a second'}</SvgText>
    <SvgText x={x0} y={156} fontSize={10.5} fontWeight="600" fill={c.label}>{'Bluetooth · about 11 a second, combined'}</SvgText>
    <SvgText x={160} y={186} fontSize={10.5} fill={c.secondaryLabel} textAnchor="middle">{'Hold to Point or Always On'}</SvgText>
  </Canvas>;
}

// ---------- 8. The Mac moves the cursor smoothly ----------
function MacDiagram({ w, c, reduce }: DiagramProps) {
  const t = useClock(reduce, 0.35);
  const inDots = Array.from({ length: 9 }, (_, i) => burstPos(i, (t * 0.22) % 1));
  const outDots = Array.from({ length: 14 }, (_, i) => ((t * 0.5 + i / 14) % 1));
  return <Canvas w={w} c={c}>
    <SvgText x={20} y={24} fontSize={11} fontWeight="600" fill={c.label}>{'Notes arrive in bursts'}</SvgText>
    <Line x1={20} y1={50} x2={150} y2={50} stroke={c.separator} strokeDasharray="2 5" />
    {inDots.map((u, i) => <Circle key={`i${i}`} cx={20 + u * 130} cy={50} r={5} fill={c.warning} />)}
    <Rect x={150} y={36} width={20} height={128} rx={10} fill={c.tint} fillOpacity={0.18} stroke={c.tint} strokeOpacity={0.6} />
    <SvgText x={160} y={104} fontSize={10} fontWeight="700" fill={c.label} textAnchor="middle" rotation={-90} origin="160,100">{'MAC'}</SvgText>
    <SvgText x={20} y={118} fontSize={11} fontWeight="600" fill={c.label}>{'Cursor glides evenly'}</SvgText>
    <Line x1={20} y1={146} x2={300} y2={146} stroke={c.separator} strokeDasharray="2 5" />
    {outDots.map((u, i) => <Circle key={`o${i}`} cx={20 + u * 280} cy={146} r={4.5} fill={c.tint} fillOpacity={0.35 + 0.65 * u} />)}
    <SvgText x={298} y={24} fontSize={10.5} fill={c.secondaryLabel} textAnchor="end">{'up to 120 a second'}</SvgText>
    <SvgText x={298} y={184} fontSize={10.5} fill={c.secondaryLabel} textAnchor="end">{'late note? it keeps gliding'}</SvgText>
  </Canvas>;
}

// ---------- 9. Summary chain ----------
const CHAIN: [SymbolName, string][] = [
  ['gyroscope', 'Gyroscope'],
  ['minus.circle', 'Remove drift'],
  ['waveform.path', 'Smooth'],
  ['multiply.circle', '× time × calibration'],
  ['paperplane.fill', 'Message'],
  ['laptopcomputer', 'Mac smooths'],
  ['cursorarrow', 'Cursor'],
];
function ChainDiagram({ w, c, reduce }: DiagramProps) {
  const t = useClock(reduce, 6.5);
  const active = Math.floor(t / 0.7) % (CHAIN.length + 2);
  return <View style={[styles.panel, { width: w, backgroundColor: c.card, borderColor: c.separator, gap: 0 }]}>
    {CHAIN.map(([icon, label], i) => {
      const on = active >= i;
      return <View key={label}>
        <View style={styles.chainRow}>
          <View style={[styles.chainIcon, { backgroundColor: on ? c.tint : c.fillStrong }]}><Icon name={icon} size={15} color={on ? c.onTint : c.secondaryLabel} /></View>
          <T v="subhead" weight="600" color={on ? c.label : c.secondaryLabel}>{label}</T>
        </View>
        {i < CHAIN.length - 1 ? <View style={[styles.chainLink, { backgroundColor: active > i ? c.tint : c.fillStrong }]} /> : null}
      </View>;
    })}
  </View>;
}

const STEPS: Step[] = [
  { title: 'The gyroscope measures turning speed.', body: "It doesn't know where you point. It only knows how fast you are turning, and it checks 100 times a second.", Diagram: GyroDiagram },
  { title: 'Three directions.', body: 'Turn left or right and the cursor moves sideways. Tilt the top up or down and it moves up or down.', extra: 'Twisting your wrist is ignored.', Diagram: AxesDiagram },
  { title: 'Removing the drift.', body: 'Even lying still, the sensor reads a tiny bit wrong. This is called bias. During calibration, AirMouse measures it while the phone rests on the screen for 2 seconds, then subtracts it.', extra: "So the cursor doesn't creep by itself.", Diagram: DriftDiagram },
  { title: 'Calming shaky hands.', body: 'A smart filter, the One Euro filter, smooths slow, shaky movements but lets quick moves through instantly. Tiny wobbles are squashed to almost zero.', Diagram: SmoothDiagram },
  { title: 'Speed × time = distance.', body: 'Turning speed × time × your calibration setting gives how many dots the cursor moves. About 29° per second for 10 ms is about 7 dots, so about 700 dots in one second.', extra: 'Flicking fast adds a little extra (acceleration).', Diagram: EquationDiagram },
  { title: 'Calibration sets the scale.', body: 'Pointing at 5 dots teaches AirMouse how many dots one degree of turning should be, separately for sideways and up/down.', Diagram: CalibrationDiagram },
  { title: 'A tiny message to your Mac.', body: 'The phone sends a short note. Wi-Fi sends about 100 a second. Bluetooth sends about 11, and notes that cannot be sent in time are combined.', extra: 'Only while you hold the pad, or always, if Always On is set.', Diagram: MessageDiagram },
  { title: 'The Mac moves the real cursor smoothly.', body: 'The Mac app gathers the notes and moves the cursor a little on every screen refresh, up to 120 times a second. If a note arrives late, the cursor glides instead of stopping.', Diagram: MacDiagram },
  { title: 'The whole chain.', body: 'From a turn of your wrist to a moving cursor.', extra: 'The accelerometer and proximity sensor are only used during calibration. The touchscreen clicks and turns pointing on and off.', Diagram: ChainDiagram },
];

export function SensorToCursorFlow({ visible, onDone }: Props) {
  const c = usePalette();
  const insets = useSafeAreaInsets();
  const reduceMotion = useReduceMotion();
  const { width } = useWindowDimensions();
  const [index, setIndex] = useState(0);
  const enter = useAnimatedValue(1);
  const step = STEPS[index];
  const last = index === STEPS.length - 1;
  const close = () => { setIndex(0); onDone(); };
  const next = () => last ? close() : setIndex((n) => n + 1);
  const back = () => setIndex((n) => Math.max(0, n - 1));

  useEffect(() => {
    enter.setValue(0);
    Animated.timing(enter, { toValue: 1, duration: reduceMotion ? 0 : 240, useNativeDriver: true }).start();
  }, [index, enter, reduceMotion]);

  const responder = PanResponder.create({
    onMoveShouldSetPanResponder: (_, g) => Math.abs(g.dx) > 12 && Math.abs(g.dx) > Math.abs(g.dy),
    onPanResponderRelease: (_, g) => { if (g.dx < -50) next(); else if (g.dx > 50) back(); },
  });
  const translateX = enter.interpolate({ inputRange: [0, 1], outputRange: [reduceMotion ? 0 : 18, 0] });
  const art = Math.min(width - space.margin * 2, 360);
  const Diagram = step.Diagram;

  return <Modal visible={visible} animationType="fade" presentationStyle="fullScreen" onRequestClose={close}>
    <View style={[styles.root, { backgroundColor: c.grouped, paddingTop: insets.top + space.sm, paddingBottom: insets.bottom + space.lg }]}>
      <View style={styles.header}>
        <Pressable onPress={back} disabled={index === 0} style={[styles.back, index === 0 && { opacity: 0 }]} accessibilityLabel="Back"><Icon name="chevron.left" size={17} color={c.tint} /><T color={c.tint}>Back</T></Pressable>
        <View style={styles.dots}>{STEPS.map((s, i) => <View key={s.title} style={[styles.dot, { width: i === index ? 22 : 7, backgroundColor: i === index ? c.tint : c.fillStrong }]} />)}</View>
        <Pressable onPress={close} hitSlop={12} accessibilityLabel="Close"><T color={c.secondaryLabel}>Close</T></Pressable>
      </View>
      <Animated.View {...responder.panHandlers} style={[styles.stage, { opacity: enter, transform: [{ translateX }] }]}>
        <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
          {visible ? <Diagram key={index} w={art} c={c} reduce={reduceMotion} /> : null}
          <View style={styles.copy}>
            <T v="title2" center>{step.title}</T>
            <T v="body" color={c.secondaryLabel} center style={styles.body}>{step.body}</T>
            {step.extra ? <T v="footnote" color={c.tint} center>{step.extra}</T> : null}
          </View>
        </ScrollView>
      </Animated.View>
      <PrimaryButton title={last ? 'Done' : 'Next'} onPress={next} />
    </View>
  </Modal>;
}

const styles = StyleSheet.create({
  root: { flex: 1, paddingHorizontal: space.margin },
  header: { height: 44, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  back: { flexDirection: 'row', alignItems: 'center', gap: 4, minWidth: 70 },
  dots: { flexDirection: 'row', gap: 5, alignItems: 'center' },
  dot: { height: 7, borderRadius: 4 },
  stage: { flex: 1 },
  scroll: { flexGrow: 1, alignItems: 'center', justifyContent: 'center', gap: space.lg, paddingVertical: space.md },
  copy: { alignItems: 'center', gap: space.sm, maxWidth: 350 },
  body: { maxWidth: 350 },
  panel: { borderRadius: radius.card + 2, borderWidth: 1, padding: space.lg, gap: space.sm },
  eqRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 4 },
  chip: { flex: 1, minWidth: 0, alignItems: 'center', paddingVertical: 8, borderRadius: 12, borderWidth: 1.5 },
  rule: { height: StyleSheet.hairlineWidth, marginVertical: space.xs },
  counterRow: { flexDirection: 'row', alignItems: 'baseline', gap: 6 },
  track: { height: 8, borderRadius: 4, overflow: 'hidden' },
  fillBar: { height: 8, borderRadius: 4 },
  chainRow: { flexDirection: 'row', alignItems: 'center', gap: space.md },
  chainIcon: { width: 28, height: 28, borderRadius: 14, alignItems: 'center', justifyContent: 'center' },
  chainLink: { width: 2, height: 10, marginLeft: 13 },
});
