import { Children, Fragment, isValidElement, useEffect, useRef, useState, type ReactNode } from 'react';
import {
  ActivityIndicator,
  Animated,
  Platform,
  Pressable,
  StyleSheet,
  Switch,
  Text,
  View,
  type GestureResponderEvent,
  type StyleProp,
  type TextStyle,
  type ViewStyle,
  useAnimatedValue,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { SymbolView, type SymbolViewProps } from 'expo-symbols';
import { BlurView } from 'expo-blur';
import { GlassView, isGlassEffectAPIAvailable, isLiquidGlassAvailable } from 'expo-glass-effect';
import Slider from '@react-native-community/slider';
import * as Haptics from 'expo-haptics';
import { TouchSet } from './touches';
import { aurora, radius, roundedFont, space, spring, tabular, type, usePalette, type Palette } from './tokens';

export type SymbolName = SymbolViewProps['name'];

// ---------- Text ----------

type Variant = keyof typeof type;
export function T(p: {
  v?: Variant;
  color?: string;
  rounded?: boolean;
  style?: StyleProp<TextStyle>;
  children: ReactNode;
  numberOfLines?: number;
  center?: boolean;
  weight?: TextStyle['fontWeight'];
}) {
  const c = usePalette();
  return (
    <Text
      numberOfLines={p.numberOfLines}
      maxFontSizeMultiplier={1.6}
      style={[
        type[p.v ?? 'body'],
        { color: p.color ?? c.label },
        p.rounded && [roundedFont, tabular],
        p.center && { textAlign: 'center' },
        p.weight ? { fontWeight: p.weight } : null,
        p.style,
      ]}
    >
      {p.children}
    </Text>
  );
}

// ---------- Icon ----------

export function Icon(p: { name: SymbolName; size?: number; color?: string; weight?: SymbolViewProps['weight']; style?: StyleProp<ViewStyle> }) {
  const size = p.size ?? 22;
  return (
    <SymbolView
      name={p.name}
      size={size}
      tintColor={p.color}
      weight={p.weight ?? 'medium'}
      resizeMode="scaleAspectFit"
      style={[{ width: size, height: size }, p.style]}
      fallback={<View style={{ width: size, height: size }} />}
    />
  );
}

// ---------- Materials ----------

let glassChecked: boolean | null = null;
export function glassAvailable(): boolean {
  if (glassChecked !== null) return glassChecked;
  try {
    glassChecked = Platform.OS === 'ios' && isLiquidGlassAvailable() && isGlassEffectAPIAvailable();
  } catch {
    glassChecked = false;
  }
  return glassChecked;
}

// Liquid Glass on iOS 26+, system blur material otherwise.
export function Material(p: { style?: StyleProp<ViewStyle>; children?: ReactNode; interactive?: boolean; tint?: string }) {
  const c = usePalette();
  if (glassAvailable()) {
    return (
      <GlassView style={p.style} glassEffectStyle="regular" isInteractive={p.interactive} tintColor={p.tint}>
        {p.children}
      </GlassView>
    );
  }
  return (
    <BlurView style={[p.style, { overflow: 'hidden' }]} intensity={80} tint={c.dark ? 'systemChromeMaterialDark' : 'systemChromeMaterialLight'}>
      {p.children}
    </BlurView>
  );
}

// ---------- Card ----------

export function Card(p: { style?: StyleProp<ViewStyle>; children: ReactNode; padded?: boolean }) {
  const c = usePalette();
  return (
    <View style={[styles.card, { backgroundColor: c.card }, p.padded !== false && { padding: space.lg }, p.style]}>{p.children}</View>
  );
}

// ---------- Inset grouped list ----------

export function Section(p: { header?: string; footer?: ReactNode; children: ReactNode; style?: StyleProp<ViewStyle> }) {
  const c = usePalette();
  const rows = Children.toArray(p.children).filter(isValidElement);
  return (
    <View style={[styles.section, p.style]}>
      {p.header ? (
        <T v="footnote" color={c.secondaryLabel} style={styles.sectionHeader}>
          {p.header.toUpperCase()}
        </T>
      ) : null}
      <View style={[styles.sectionBody, { backgroundColor: c.card }]}>
        {rows.map((row, i) => (
          <Fragment key={i}>
            {i > 0 ? <View style={[styles.separator, { backgroundColor: c.separator }]} /> : null}
            {row}
          </Fragment>
        ))}
      </View>
      {p.footer ? (
        typeof p.footer === 'string' ? (
          <T v="footnote" color={c.secondaryLabel} style={styles.sectionFooter}>
            {p.footer}
          </T>
        ) : (
          <View style={styles.sectionFooter}>{p.footer}</View>
        )
      ) : null}
    </View>
  );
}

// Rounded-square icon badge, like Settings.app.
export function IconBadge(p: { name: SymbolName; color: string; gradient?: boolean; size?: number }) {
  const size = p.size ?? 30;
  const inner = <Icon name={p.name} size={size * 0.6} color="#FFFFFF" weight="semibold" />;
  if (p.gradient) {
    return (
      <LinearGradient colors={aurora.colors} start={aurora.start} end={aurora.end} style={[styles.badge, { width: size, height: size, borderRadius: size * 0.26 }]}>
        {inner}
      </LinearGradient>
    );
  }
  return <View style={[styles.badge, { width: size, height: size, borderRadius: size * 0.26, backgroundColor: p.color }]}>{inner}</View>;
}

export function ListRow(p: {
  title: string;
  subtitle?: string;
  icon?: SymbolName;
  iconColor?: string;
  iconGradient?: boolean;
  value?: string;
  valueRounded?: boolean;
  chevron?: boolean;
  onPress?: () => void;
  destructive?: boolean;
  tinted?: boolean;
  disabled?: boolean;
  right?: ReactNode;
  loading?: boolean;
}) {
  const c = usePalette();
  const titleColor = p.destructive ? c.errorText : p.tinted ? c.tint : c.label;
  const content = (pressed: boolean) => (
    <View style={[styles.row, pressed && { backgroundColor: c.fill }, p.disabled && { opacity: 0.4 }]}>
      {p.icon ? <IconBadge name={p.icon} color={p.iconColor ?? c.tint} gradient={p.iconGradient} /> : null}
      <View style={{ flex: 1, gap: 1 }}>
        <T color={titleColor} numberOfLines={1}>
          {p.title}
        </T>
        {p.subtitle ? (
          <T v="footnote" color={c.secondaryLabel} numberOfLines={2}>
            {p.subtitle}
          </T>
        ) : null}
      </View>
      {p.value ? (
        <T color={c.secondaryLabel} rounded={p.valueRounded} numberOfLines={1} style={{ maxWidth: '55%' }}>
          {p.value}
        </T>
      ) : null}
      {p.loading ? <ActivityIndicator /> : null}
      {p.right}
      {p.chevron ? <Icon name="chevron.right" size={14} color={c.tertiaryLabel} weight="semibold" /> : null}
    </View>
  );
  if (!p.onPress) return content(false);
  return (
    <Pressable onPress={p.onPress} disabled={p.disabled} accessibilityRole="button" accessibilityLabel={p.title}>
      {({ pressed }) => content(pressed)}
    </Pressable>
  );
}

export function SwitchRow(p: { title: string; subtitle?: string; icon?: SymbolName; iconColor?: string; value: boolean; onChange: (v: boolean) => void }) {
  const c = usePalette();
  return (
    <ListRow
      title={p.title}
      subtitle={p.subtitle}
      icon={p.icon}
      iconColor={p.iconColor}
      right={<Switch value={p.value} onValueChange={p.onChange} trackColor={{ true: c.success }} />}
    />
  );
}

// Slider with live value; commits on release so storage is not hammered.
export function SliderRow(p: {
  title: string;
  value: number;
  min: number;
  max: number;
  step?: number;
  format: (v: number) => string;
  onCommit: (v: number) => void;
  onLive?: (v: number) => void; // every move, for previews that must react while dragging
  minLabel?: string;
  maxLabel?: string;
  minIcon?: SymbolName;
  maxIcon?: SymbolName;
}) {
  const c = usePalette();
  const [live, setLive] = useState(p.value);
  const [prev, setPrev] = useState(p.value);
  if (prev !== p.value) {
    setPrev(p.value);
    setLive(p.value);
  }
  return (
    <View style={styles.sliderRow}>
      <View style={styles.sliderHead}>
        <T>{p.title}</T>
        <T color={c.secondaryLabel} rounded weight="500">
          {p.format(live)}
        </T>
      </View>
      <View style={styles.sliderLine}>
        {p.minIcon ? <Icon name={p.minIcon} size={16} color={c.secondaryLabel} /> : null}
        <Slider
          style={{ flex: 1, height: 34 }}
          minimumValue={p.min}
          maximumValue={p.max}
          step={p.step}
          value={p.value}
          minimumTrackTintColor={c.tint}
          onValueChange={(v) => {
            setLive(v);
            p.onLive?.(v);
          }}
          onSlidingComplete={(v) => {
            Haptics.selectionAsync();
            p.onCommit(v);
          }}
          accessibilityLabel={p.title}
        />
        {p.maxIcon ? <Icon name={p.maxIcon} size={16} color={c.secondaryLabel} /> : null}
      </View>
      {p.minLabel || p.maxLabel ? (
        <View style={styles.sliderHead}>
          <T v="caption" color={c.secondaryLabel}>
            {p.minLabel}
          </T>
          <T v="caption" color={c.secondaryLabel}>
            {p.maxLabel}
          </T>
        </View>
      ) : null}
    </View>
  );
}

// ---------- Segmented control ----------

export function SegmentedControl<K extends string>(p: {
  options: { key: K; label: string; disabled?: boolean }[];
  value: K;
  onChange: (k: K) => void;
  style?: StyleProp<ViewStyle>;
}) {
  const c = usePalette();
  const [w, setW] = useState(0);
  const index = Math.max(0, p.options.findIndex((o) => o.key === p.value));
  const x = useAnimatedValue(0);
  const seg = w > 0 ? (w - 4) / p.options.length : 0;
  useEffect(() => {
    Animated.spring(x, { toValue: index * seg, useNativeDriver: true, ...spring }).start();
  }, [index, seg, x]);
  return (
    <View style={[styles.segment, { backgroundColor: c.fill }, p.style]} onLayout={(e) => setW(e.nativeEvent.layout.width)}>
      {seg > 0 ? (
        <Animated.View
          style={[
            styles.segmentThumb,
            { width: seg, backgroundColor: c.dark ? '#636366' : '#FFFFFF', transform: [{ translateX: x }] },
          ]}
        />
      ) : null}
      {p.options.map((o) => (
        <Pressable
          key={o.key}
          disabled={o.disabled}
          style={[styles.segmentItem, o.disabled && { opacity: 0.35 }]}
          onPress={() => {
            if (o.key !== p.value) Haptics.selectionAsync();
            p.onChange(o.key);
          }}
          accessibilityRole="button"
          accessibilityState={{ selected: o.key === p.value, disabled: o.disabled }}
        >
          <T v="subhead" weight={o.key === p.value ? '600' : '500'} numberOfLines={1}>
            {o.label}
          </T>
        </Pressable>
      ))}
    </View>
  );
}

// ---------- Buttons ----------

function usePressScale() {
  const scale = useAnimatedValue(1);
  const to = (v: number) => Animated.spring(scale, { toValue: v, useNativeDriver: true, damping: 15, stiffness: 300 }).start();
  return { scale, onPressIn: () => to(0.96), onPressOut: () => to(1) };
}

export function PrimaryButton(p: { title: string; icon?: SymbolName; onPress: () => void; disabled?: boolean; loading?: boolean; style?: StyleProp<ViewStyle>; compact?: boolean }) {
  const { scale, onPressIn, onPressOut } = usePressScale();
  return (
    <Animated.View style={[{ transform: [{ scale }] }, p.disabled && { opacity: 0.45 }, p.style]}>
      <Pressable onPress={p.onPress} onPressIn={onPressIn} onPressOut={onPressOut} disabled={p.disabled || p.loading} accessibilityRole="button" accessibilityLabel={p.title}>
        <LinearGradient colors={aurora.colors} start={aurora.start} end={aurora.end} style={[styles.primary, p.compact && styles.primaryCompact]}>
          {p.loading ? <ActivityIndicator color="#FFFFFF" /> : p.icon ? <Icon name={p.icon} size={19} color="#FFFFFF" weight="semibold" /> : null}
          <T v="headline" color="#FFFFFF">
            {p.title}
          </T>
        </LinearGradient>
      </Pressable>
    </Animated.View>
  );
}

export function SecondaryButton(p: { title: string; icon?: SymbolName; onPress: () => void; disabled?: boolean; style?: StyleProp<ViewStyle>; plain?: boolean; color?: string }) {
  const c = usePalette();
  const { scale, onPressIn, onPressOut } = usePressScale();
  const color = p.color ?? c.tint;
  return (
    <Animated.View style={[{ transform: [{ scale }] }, p.disabled && { opacity: 0.45 }, p.style]}>
      <Pressable onPress={p.onPress} onPressIn={onPressIn} onPressOut={onPressOut} disabled={p.disabled} accessibilityRole="button" accessibilityLabel={p.title}>
        <View style={[styles.secondary, !p.plain && { backgroundColor: c.fill }]}>
          {p.icon ? <Icon name={p.icon} size={18} color={color} weight="semibold" /> : null}
          <T v="headline" color={color}>
            {p.title}
          </T>
        </View>
      </Pressable>
    </Animated.View>
  );
}

// Square-ish tile with a symbol and a short label (Remote quick actions).
export function IconButton(p: {
  icon: SymbolName;
  label?: string;
  onPress?: () => void;
  onPressIn?: () => void;
  onPressOut?: () => void;
  style?: StyleProp<ViewStyle>;
  color?: string;
  size?: number;
  disabled?: boolean;
  accessibilityLabel?: string;
}) {
  const c = usePalette();
  const press = usePressScale();
  return (
    <Animated.View style={[{ transform: [{ scale: press.scale }] }, p.disabled && { opacity: 0.4 }, p.style]}>
      <Pressable
        disabled={p.disabled}
        onPress={p.onPress}
        onPressIn={() => {
          press.onPressIn();
          p.onPressIn?.();
        }}
        onPressOut={() => {
          press.onPressOut();
          p.onPressOut?.();
        }}
        accessibilityRole="button"
        accessibilityLabel={p.accessibilityLabel ?? p.label}
      >
        {({ pressed }) => (
          <View style={[styles.iconButton, { backgroundColor: pressed ? c.fillStrong : c.card }]}>
            <Icon name={p.icon} size={p.size ?? 22} color={p.color ?? c.tint} weight="semibold" />
            {p.label ? (
              <T v="footnote" weight="500" numberOfLines={1} color={c.label}>
                {p.label}
              </T>
            ) : null}
          </View>
        )}
      </Pressable>
    </Animated.View>
  );
}

// Same look as IconButton, but driven by raw touch events instead of the
// responder system, so it works while another finger holds the touch pad
// (hold pad + press Left = drag). onDown on first finger, onUp on last.
export function HoldButton(p: { icon: SymbolName; label: string; onDown: () => void; onUp: () => void; style?: StyleProp<ViewStyle> }) {
  const c = usePalette();
  const touches = useRef(new TouchSet());
  const [down, setDown] = useState(false);
  const { onDown, onUp } = p;
  const release = () => {
    setDown(false);
    onUp();
  };
  const onUpRef = useRef(onUp);
  useEffect(() => {
    onUpRef.current = onUp;
  }, [onUp]);
  // Never leave the Mac with a button stuck down if we unmount mid-press.
  useEffect(() => {
    const t = touches.current;
    return () => {
      if (t.clear()) onUpRef.current();
    };
  }, []);
  return (
    <View
      style={[styles.iconButton, { backgroundColor: down ? c.fillStrong : c.card, transform: [{ scale: down ? 0.96 : 1 }] }, p.style]}
      onTouchStart={(e: GestureResponderEvent) => {
        if (touches.current.down(e.nativeEvent.identifier)) {
          setDown(true);
          onDown();
        }
      }}
      onTouchEnd={(e: GestureResponderEvent) => {
        const n = e.nativeEvent;
        if (touches.current.up([n, ...n.changedTouches]) || touches.current.sync(n.touches)) release();
      }}
      onTouchCancel={() => touches.current.clear() && release()}
      accessible
      accessibilityRole="button"
      accessibilityLabel={p.label}
      onAccessibilityTap={() => {
        onDown();
        onUp();
      }}
    >
      <Icon name={p.icon} size={22} color={c.tint} weight="semibold" />
      <T v="footnote" weight="500" numberOfLines={1} color={c.label}>
        {p.label}
      </T>
    </View>
  );
}

// ---------- Status pill ----------

export function StatusPill(p: { label: string; color: string; onPress?: () => void; pulse?: boolean; icon?: SymbolName }) {
  const c = usePalette();
  const o = useAnimatedValue(1);
  useEffect(() => {
    if (!p.pulse) {
      o.setValue(1);
      return;
    }
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(o, { toValue: 0.3, duration: 650, useNativeDriver: true }),
        Animated.timing(o, { toValue: 1, duration: 650, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [p.pulse, o]);
  return (
    <Pressable onPress={p.onPress} accessibilityRole="button" accessibilityLabel={p.label}>
      {({ pressed }) => (
        <Material style={[styles.pill, pressed && { opacity: 0.7 }]} interactive>
          <Animated.View style={[styles.dot, { backgroundColor: p.color, opacity: o }]} />
          {p.icon ? <Icon name={p.icon} size={15} color={c.secondaryLabel} /> : null}
          <T v="subhead" weight="600" numberOfLines={1} style={{ flexShrink: 1 }}>
            {p.label}
          </T>
          {p.onPress ? <Icon name="chevron.down" size={11} color={c.secondaryLabel} weight="bold" /> : null}
        </Material>
      )}
    </Pressable>
  );
}

// ---------- Screen chrome ----------

export function LargeTitle(p: { title: string; subtitle?: string; right?: ReactNode }) {
  const c = usePalette();
  return (
    <View style={styles.largeTitle}>
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
        <T v="largeTitle">{p.title}</T>
        {p.right}
      </View>
      {p.subtitle ? (
        <T v="subhead" color={c.secondaryLabel}>
          {p.subtitle}
        </T>
      ) : null}
    </View>
  );
}

export function paletteStatusColor(c: Palette, status: 'idle' | 'connecting' | 'open' | 'error'): string {
  return status === 'open' ? c.success : status === 'connecting' ? c.warning : status === 'error' ? c.error : c.tertiaryLabel;
}

const styles = StyleSheet.create({
  card: { borderRadius: radius.card, borderCurve: 'continuous' },
  section: { gap: 7 },
  sectionHeader: { paddingHorizontal: space.lg, letterSpacing: 0 },
  sectionBody: { borderRadius: radius.card - 4, borderCurve: 'continuous', overflow: 'hidden' },
  sectionFooter: { paddingHorizontal: space.lg },
  separator: { height: StyleSheet.hairlineWidth, marginLeft: space.lg },
  row: { minHeight: 52, flexDirection: 'row', alignItems: 'center', gap: space.md, paddingHorizontal: space.lg, paddingVertical: 10 },
  badge: { alignItems: 'center', justifyContent: 'center', borderCurve: 'continuous' },
  sliderRow: { paddingHorizontal: space.lg, paddingTop: 12, paddingBottom: 8 },
  sliderHead: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  sliderLine: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  segment: { height: 36, borderRadius: 10, borderCurve: 'continuous', padding: 2, flexDirection: 'row' },
  segmentThumb: {
    position: 'absolute',
    top: 2,
    left: 2,
    bottom: 2,
    borderRadius: 8,
    borderCurve: 'continuous',
    shadowColor: '#000',
    shadowOpacity: 0.12,
    shadowRadius: 4,
    shadowOffset: { width: 0, height: 2 },
  },
  segmentItem: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 4 },
  primary: {
    height: 54,
    borderRadius: radius.button + 2,
    borderCurve: 'continuous',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: space.sm,
    paddingHorizontal: space.xl,
  },
  primaryCompact: { height: 40, borderRadius: 20, paddingHorizontal: space.lg },
  secondary: {
    height: 50,
    borderRadius: radius.button,
    borderCurve: 'continuous',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: space.sm,
    paddingHorizontal: space.xl,
  },
  iconButton: { minHeight: 64, borderRadius: radius.button + 4, borderCurve: 'continuous', alignItems: 'center', justifyContent: 'center', gap: 5, paddingVertical: 10 },
  pill: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 14, height: 38, borderRadius: 19, maxWidth: 300 },
  dot: { width: 9, height: 9, borderRadius: 4.5 },
  largeTitle: { paddingHorizontal: space.margin, paddingTop: space.sm, paddingBottom: space.md, gap: 2 },
});

// Compact "something is off" row that reopens a Setup step.
export function WarningRow(p: { text: string; action?: string; onPress: () => void }) {
  const c = usePalette();
  return (
    <Pressable onPress={p.onPress} accessibilityRole="button" accessibilityLabel={`${p.text}. ${p.action ?? 'Fix'}`}>
      {({ pressed }) => (
        <View style={[warnStyles.row, { backgroundColor: c.dark ? 'rgba(255,159,10,0.16)' : 'rgba(255,159,10,0.14)' }, pressed && { opacity: 0.7 }]}>
          <Icon name="exclamationmark.triangle.fill" size={16} color={c.warning} />
          <T v="subhead" weight="500" style={{ flex: 1 }} numberOfLines={2}>
            {p.text}
          </T>
          <T v="subhead" weight="600" color={c.tint}>
            {p.action ?? 'Fix'}
          </T>
        </View>
      )}
    </Pressable>
  );
}

const warnStyles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 14, minHeight: 44, paddingVertical: 8, borderRadius: 14, borderCurve: 'continuous' },
});

// ---------- Mac-matching pieces: gradient icon circle, tag chip, step ring ----------

export const CIRCLE_GRADIENTS = {
  blue: ['#4AA3FF', '#0A64F0'],
  indigo: ['#8A7DFF', '#4B48D6'],
  purple: ['#D68BFF', '#9F45E0'],
  teal: ['#4FD8E0', '#14A7B8'],
  green: ['#5BE07F', '#22B04A'],
  orange: ['#FFC15A', '#FF8A00'],
  aurora: ['#0A84FF', '#BF5AF2'],
} as const;
export type CircleTone = keyof typeof CIRCLE_GRADIENTS;

export function IconCircle(p: { name: SymbolName; tone: CircleTone; size?: number; dot?: string }) {
  const size = p.size ?? 36;
  const g = CIRCLE_GRADIENTS[p.tone];
  return (
    <View style={{ width: size, height: size }}>
      <LinearGradient colors={g} start={{ x: 0.2, y: 0 }} end={{ x: 0.8, y: 1 }} style={{ width: size, height: size, borderRadius: size / 2, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={p.name} size={size * 0.5} color="#FFFFFF" weight="semibold" />
      </LinearGradient>
      {p.dot ? <View style={[circleStyles.dot, { backgroundColor: p.dot, width: size * 0.3, height: size * 0.3, borderRadius: size * 0.15 }]} /> : null}
    </View>
  );
}

export function Tag(p: { text: string }) {
  const c = usePalette();
  return (
    <View style={[circleStyles.tag, { backgroundColor: c.fill }]}>
      <T v="caption" weight="600" color={c.secondaryLabel}>
        {p.text}
      </T>
    </View>
  );
}

// Progress ring with "3/4" in the middle (Mac Permissions header).
export function StepRing(p: { done: number; total: number; size?: number }) {
  const c = usePalette();
  const size = p.size ?? 58;
  const all = p.done >= p.total;
  return (
    <View style={[circleStyles.ring, { width: size, height: size, borderRadius: size / 2, borderColor: all ? c.success : c.tint }]}>
      <T v="subhead" weight="700" rounded>
        {p.done}/{p.total}
      </T>
    </View>
  );
}

const circleStyles = StyleSheet.create({
  dot: { position: 'absolute', right: -1, bottom: -1, borderWidth: 2, borderColor: '#FFFFFF' },
  tag: { paddingHorizontal: 7, paddingVertical: 2, borderRadius: 7 },
  ring: { borderWidth: 4, alignItems: 'center', justifyContent: 'center' },
});
