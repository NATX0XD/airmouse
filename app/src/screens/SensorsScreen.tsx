import { useEffect, useRef, useState, type RefObject } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Accelerometer } from 'expo-sensors';
import type { GyroSample } from '../motion/engine';
import { SensorChart } from '../components/SensorChart';
import { Card, Icon, LargeTitle, T, type SymbolName } from '../ui/components';
import { space, usePalette } from '../ui/tokens';
import { TAB_BAR_SPACE } from '../ui/TabBar';
import { Illustration } from '../ui/Illustration';

type Props = { gyroHistory: RefObject<GyroSample[]>; demo?: boolean; initialScroll?: number };

const REDRAW_MS = 60; // chart refresh; sensors themselves run faster
const ACCEL_KEEP = 60;

export function SensorsScreen({ gyroHistory, demo, initialScroll }: Props) {
  const c = usePalette();
  const insets = useSafeAreaInsets();
  type Vec = { x: number; y: number; z: number };
  const accel = useRef<Vec[]>([]);
  const [snap, setSnap] = useState<{ g: GyroSample[]; a: Vec[] }>({ g: [], a: [] });

  useEffect(() => {
    let sub: { remove(): void } | null = null;
    Accelerometer.isAvailableAsync()
      .then((ok) => {
        if (!ok) return;
        Accelerometer.setUpdateInterval(50);
        sub = Accelerometer.addListener((a) => {
          accel.current.push(a);
          if (accel.current.length > ACCEL_KEEP) accel.current.shift();
        });
      })
      .catch(() => {});
    // demo = screenshot builds on the Simulator (no sensors): synthetic waves.
    const wave = (n: number, f: number, amp: number, ph: number, t: number) => Array.from({ length: n }, (_, i) => amp * Math.sin((i + t) * f + ph) * Math.exp(-(((i - n * 0.6) / (n * 0.35)) ** 2)));
    const fake = (t: number) => {
      const gx = wave(150, 0.09, 1.1, 0, t);
      const gy = wave(150, 0.05, 0.5, 1, t);
      const gz = wave(150, 0.07, 2.3, 2, t);
      const ax = wave(60, 0.2, 0.25, 0, t);
      const ay = wave(60, 0.15, 0.2, 1, t);
      return {
        g: gx.map((x, i) => ({ x, y: gy[i], z: gz[i], timestamp: i / 60 })),
        a: ax.map((x, i) => ({ x, y: ay[i], z: -0.98 + 0.05 * Math.sin(i * 0.3) })),
      };
    };
    let tick = 0;
    const id = setInterval(() => setSnap(demo ? fake((tick += 1)) : { g: [...(gyroHistory.current ?? [])], a: [...accel.current] }), REDRAW_MS);
    return () => {
      sub?.remove();
      clearInterval(id);
    };
  }, [gyroHistory, demo]);

  const { g, a } = snap;

  return (
    <ScrollView
      contentContainerStyle={{ paddingTop: insets.top, paddingBottom: insets.bottom + TAB_BAR_SPACE + space.lg }}
      contentInsetAdjustmentBehavior="never"
      contentOffset={initialScroll ? { x: 0, y: initialScroll } : undefined}
    >
      <LargeTitle title="Sensors" subtitle="What your iPhone feels, live." />
      <View style={styles.body}>
        <SensorChart
          title="Gyroscope"
          subtitle="Rotation speed, 100 times a second"
          icon="gyroscope"
          iconColor="#5E5CE6"
          unit="rad/s"
          range={4}
          series={[
            { label: 'X', color: c.axisX, values: g.map((s) => s.x) },
            { label: 'Y', color: c.axisY, values: g.map((s) => s.y) },
            { label: 'Z', color: c.axisZ, values: g.map((s) => s.z) },
          ]}
        />
        <SensorChart
          title="Accelerometer"
          subtitle="Gravity and shakes, 20 times a second"
          icon="move.3d"
          iconColor="#FF9F0A"
          unit="g"
          range={2}
          series={[
            { label: 'X', color: c.axisX, values: a.map((s) => s.x) },
            { label: 'Y', color: c.axisY, values: a.map((s) => s.y) },
            { label: 'Z', color: c.axisZ, values: a.map((s) => s.z) },
          ]}
        />
        <Card style={{ gap: space.lg }}>
          <T v="headline">How AirMouse Uses Them</T>
          <View style={{ alignItems: 'center' }}>
            <Illustration name="gyro-axes" width={300} height={200} />
          </View>
          <Explain icon="arrow.left.and.right" color={c.axisZ} title="Turn left or right" body="Rotation around Z moves the pointer sideways." />
          <Explain icon="arrow.up.and.down" color={c.axisX} title="Tip up or down" body="Rotation around X moves the pointer up and down." />
          <Explain icon="hand.wave" color="#BF5AF2" title="Flick" body="A short, fast turn changes slides." />
          <Explain icon="scope" color="#30D158" title="Hold still" body="Calibration averages the resting gyro to remove drift." />
          <T v="footnote" color={c.secondaryLabel}>
            The gyroscope reports speed, not angle: held still, every axis returns to about 0. Lying flat, the accelerometer reads about 1 g on the axis pointing up.
          </T>
        </Card>
      </View>
    </ScrollView>
  );
}

function Explain(p: { icon: SymbolName; color: string; title: string; body: string }) {
  const c = usePalette();
  return (
    <View style={styles.explain}>
      <View style={[styles.explainIcon, { backgroundColor: c.fill }]}>
        <Icon name={p.icon} size={18} color={p.color} weight="semibold" />
      </View>
      <View style={{ flex: 1 }}>
        <T v="subhead" weight="600">
          {p.title}
        </T>
        <T v="subhead" color={c.secondaryLabel}>
          {p.body}
        </T>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  body: { paddingHorizontal: space.lg, gap: space.lg },
  explain: { flexDirection: 'row', gap: space.md, alignItems: 'center' },
  explainIcon: { width: 36, height: 36, borderRadius: 18, alignItems: 'center', justifyContent: 'center' },
});
