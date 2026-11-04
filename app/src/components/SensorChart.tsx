import { useState } from 'react';
import { StyleSheet, View, type LayoutChangeEvent } from 'react-native';
import Svg, { Line, Polyline } from 'react-native-svg';
import { Card, IconBadge, T, type SymbolName } from '../ui/components';
import { space, usePalette } from '../ui/tokens';

export type Series = { label: string; color: string; values: number[] };

type Props = { title: string; subtitle: string; icon: SymbolName; iconColor: string; unit: string; range: number; series: Series[] };

const H = 132;

// Live line chart, symmetric around zero: y = 0 is the middle line.
export function SensorChart({ title, subtitle, icon, iconColor, unit, range, series }: Props) {
  const c = usePalette();
  const [w, setW] = useState(0);
  const onLayout = (e: LayoutChangeEvent) => setW(e.nativeEvent.layout.width);
  const hasData = series.some((s) => s.values.length > 1);

  const toPoints = (values: number[]) => {
    if (values.length < 2 || w === 0) return '';
    const step = w / (values.length - 1);
    return values
      .map((v, i) => {
        const clamped = Math.max(-range, Math.min(range, v));
        return `${(i * step).toFixed(1)},${(H / 2 - (clamped / range) * (H / 2 - 3)).toFixed(1)}`;
      })
      .join(' ');
  };

  return (
    <Card style={{ gap: space.md }}>
      <View style={styles.head}>
        <IconBadge name={icon} color={iconColor} />
        <View style={{ flex: 1 }}>
          <T v="headline">{title}</T>
          <T v="footnote" color={c.secondaryLabel}>
            {subtitle}
          </T>
        </View>
        <View style={[styles.chip, { backgroundColor: c.fill }]}>
          <T v="caption" color={c.secondaryLabel} rounded weight="600">
            ±{range} {unit}
          </T>
        </View>
      </View>
      <View onLayout={onLayout} style={{ height: H }}>
        {w > 0 && (
          <Svg width={w} height={H}>
            {[0.25, 0.75].map((f) => (
              <Line key={f} x1={0} y1={H * f} x2={w} y2={H * f} stroke={c.separator} strokeWidth={StyleSheet.hairlineWidth} strokeDasharray="3 4" />
            ))}
            <Line x1={0} y1={H / 2} x2={w} y2={H / 2} stroke={c.separator} strokeWidth={1} />
            {series.map((s) => (
              <Polyline key={s.label} points={toPoints(s.values)} fill="none" stroke={s.color} strokeWidth={2.2} strokeLinejoin="round" strokeLinecap="round" />
            ))}
          </Svg>
        )}
        {!hasData ? (
          <View style={[StyleSheet.absoluteFill, styles.empty]}>
            <T v="footnote" color={c.secondaryLabel} style={{ backgroundColor: c.card, paddingHorizontal: 8 }}>
              Waiting for sensor data…
            </T>
          </View>
        ) : null}
      </View>
      <View style={styles.legend}>
        {series.map((s) => {
          const last = s.values[s.values.length - 1];
          return (
            <View key={s.label} style={[styles.value, { backgroundColor: c.fill }]}>
              <View style={[styles.dot, { backgroundColor: s.color }]} />
              <T v="footnote" weight="600" color={c.secondaryLabel}>
                {s.label}
              </T>
              <T v="callout" rounded weight="600" style={{ marginLeft: 'auto' }}>
                {last === undefined ? '—' : `${last >= 0 ? ' ' : ''}${last.toFixed(2)}`}
              </T>
            </View>
          );
        })}
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  head: { flexDirection: 'row', alignItems: 'center', gap: space.md },
  chip: { paddingHorizontal: 8, paddingVertical: 3, borderRadius: 8 },
  empty: { alignItems: 'center', justifyContent: 'center' },
  legend: { flexDirection: 'row', gap: space.sm },
  value: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 10, paddingVertical: 8, borderRadius: 12, borderCurve: 'continuous' },
  dot: { width: 8, height: 8, borderRadius: 4 },
});
