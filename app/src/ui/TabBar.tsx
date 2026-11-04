import { useEffect, useState } from 'react';
import { Animated, Pressable, StyleSheet, View, useAnimatedValue } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Haptics from 'expo-haptics';
import { Icon, Material, T, type SymbolName } from './components';
import { spring, usePalette } from './tokens';
import { useTourTarget } from './Tour';

export type TabItem<K extends string> = { key: K; label: string; icon: SymbolName };

const BAR_H = 62;
// Space a screen must leave above the bottom safe area for the floating bar.
export const TAB_BAR_SPACE = BAR_H + 10;

// Floating capsule tab bar (iOS 26 style): Liquid Glass when available,
// system chrome blur otherwise. Selected tab sits on a soft pill.
export function TabBar<K extends string>(p: { tabs: TabItem<K>[]; value: K; onChange: (k: K) => void }) {
  const c = usePalette();
  const insets = useSafeAreaInsets();
  const [w, setW] = useState(0);
  const index = Math.max(0, p.tabs.findIndex((t) => t.key === p.value));
  const seg = w > 0 ? (w - 8) / p.tabs.length : 0;
  const x = useAnimatedValue(0);
  const tSettings = useTourTarget('settingsTab');
  useEffect(() => {
    Animated.spring(x, { toValue: index * seg, useNativeDriver: true, ...spring }).start();
  }, [index, seg, x]);

  return (
    <View style={[styles.wrap, { bottom: Math.max(insets.bottom - 8, 10) }]} pointerEvents="box-none">
      <Material style={styles.bar} interactive>
        <View style={styles.inner} onLayout={(e) => setW(e.nativeEvent.layout.width)}>
          {seg > 0 ? (
            <Animated.View style={[styles.thumb, { width: seg, backgroundColor: c.fill, transform: [{ translateX: x }] }]} />
          ) : null}
          {p.tabs.map((t) => {
            const on = t.key === p.value;
            return (
              <Pressable
                key={t.key}
                ref={t.key === 'settings' ? tSettings : undefined}
                style={styles.item}
                onPress={() => {
                  if (!on) Haptics.selectionAsync();
                  p.onChange(t.key);
                }}
                accessibilityRole="tab"
                accessibilityState={{ selected: on }}
                accessibilityLabel={t.label}
              >
                <Icon name={t.icon} size={23} color={on ? c.tint : c.label} weight={on ? 'semibold' : 'regular'} />
                <T v="caption" weight={on ? '600' : '500'} color={on ? c.tint : c.label} style={{ fontSize: 11, lineHeight: 13 }}>
                  {t.label}
                </T>
              </Pressable>
            );
          })}
        </View>
      </Material>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { position: 'absolute', left: 0, right: 0, alignItems: 'center' },
  bar: {
    height: BAR_H,
    width: 300,
    borderRadius: BAR_H / 2,
    shadowColor: '#000',
    shadowOpacity: 0.12,
    shadowRadius: 20,
    shadowOffset: { width: 0, height: 6 },
  },
  inner: { flex: 1, flexDirection: 'row', padding: 4 },
  thumb: { position: 'absolute', top: 4, bottom: 4, left: 4, borderRadius: (BAR_H - 8) / 2 },
  item: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 2 },
});
