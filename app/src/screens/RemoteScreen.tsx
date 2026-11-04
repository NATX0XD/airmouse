import { useEffect, useRef, useState } from 'react';
import { Animated, Pressable, StyleSheet, View, type GestureResponderEvent, useAnimatedValue } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import * as Haptics from 'expo-haptics';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import type { AppSettings, PointerMode, TransportKind } from '../settings';
import type { Button, Msg, TransportStatus } from '../transport/types';
import { HoldButton, Icon, IconButton, Material, PrimaryButton, SegmentedControl, StatusPill, T, WarningRow, paletteStatusColor, type SymbolName } from '../ui/components';
import { isTap } from '../motion/pointer';
import { TouchSet } from '../ui/touches';
import { KeyboardPanel, useKeyboardHeight } from './KeyboardPanel';
import { aurora, radius, space, usePalette, useReduceMotion } from '../ui/tokens';
import { TAB_BAR_SPACE } from '../ui/TabBar';
import { useTourTarget } from '../ui/Tour';

type Props = {
  settings: AppSettings;
  status: TransportStatus;
  kind: TransportKind | null;
  macName: string;
  gyroAvailable: boolean | null;
  send: (m: Msg) => void;
  setTouching: (v: boolean) => void;
  onOpenConnect: () => void;
  onCalibrate: () => void;
  forcePressed?: boolean;
  warning?: { text: string; onPress: () => void };
  onModeChange: (mode: PointerMode) => void;
  keyboardOpen: boolean;
  keyboardField: number;
  onKeyboard: (open: boolean) => void;
  onTyped: () => void;
  practiceRunning: boolean;
  onPractice: (start: boolean) => void;
};

// Round glass button beside the status pill.
function GlassCircle(p: { icon: SymbolName; label: string; onPress: () => void; active?: boolean; disabled?: boolean }) {
  const c = usePalette();
  return (
    <Pressable onPress={p.onPress} disabled={p.disabled} hitSlop={6} accessibilityRole="button" accessibilityLabel={p.label} accessibilityState={{ selected: p.active, disabled: p.disabled }} style={p.disabled && { opacity: 0.4 }}>
      <Material style={styles.circle} interactive tint={p.active ? c.tint : undefined}>
        <Icon name={p.icon} size={19} color={p.active ? '#FFFFFF' : c.tint} weight="semibold" />
      </Material>
    </Pressable>
  );
}
const SCROLL_STEP_PX = 14; // finger travel per scroll notch

export function RemoteScreen(p: Props) {
  const c = usePalette();
  const insets = useSafeAreaInsets();
  const reduceMotion = useReduceMotion();
  const [padDown, setPadDown] = useState(false);
  const [scrolling, setScrolling] = useState(false);
  const downAt = useRef(0);
  const padTouches = useRef(new TouchSet());
  const scrollY = useRef(0);
  const scrollAcc = useRef(0);
  const glow = useAnimatedValue(0);
  const ring = useAnimatedValue(0);
  const pressed = padDown || !!p.forcePressed;
  const connected = p.status === 'open';
  const tPill = useTourTarget('pill');
  const tPad = useTourTarget('pad');
  const tScroll = useTourTarget('scroll');
  const tClicks = useTourTarget('clicks');
  const tCenter = useTourTarget('center');
  const tCalib = useTourTarget('calibrate');
  const kbHeight = useKeyboardHeight();
  const typing = p.keyboardOpen;

  useEffect(() => {
    Animated.spring(glow, { toValue: pressed ? 1 : 0, useNativeDriver: true, damping: 20, stiffness: 260 }).start();
    if (!pressed || reduceMotion) {
      ring.setValue(0);
      return;
    }
    const loop = Animated.loop(Animated.timing(ring, { toValue: 1, duration: 1600, useNativeDriver: true }));
    loop.start();
    return () => loop.stop();
  }, [pressed, reduceMotion, glow, ring]);

  const click = (b: Button) => {
    p.send({ t: 'button', b, down: true });
    p.send({ t: 'button', b, down: false });
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
  };

  // Pad: finger down = clutch (cursor follows the phone), quick tap = click.
  // Raw touch events (not the responder), so a second finger can hold the
  // click buttons at the same time.
  const padStart = (e: GestureResponderEvent) => {
    if (!padTouches.current.down(e.nativeEvent.identifier)) return;
    downAt.current = Date.now();
    p.setTouching(true);
    setPadDown(true);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Soft);
  };
  const padEnd = (e: GestureResponderEvent) => {
    const n = e.nativeEvent;
    if (!padTouches.current.up([n, ...n.changedTouches]) && !padTouches.current.sync(n.touches)) return;
    p.setTouching(false);
    setPadDown(false);
    if (isTap(downAt.current, Date.now())) click('left');
  };
  const padCancel = () => {
    if (!padTouches.current.clear()) return;
    p.setTouching(false);
    setPadDown(false);
  };

  const scrollGrant = (e: GestureResponderEvent) => {
    scrollY.current = e.nativeEvent.pageY;
    scrollAcc.current = 0;
    setScrolling(true);
  };
  const scrollMove = (e: GestureResponderEvent) => {
    const y = e.nativeEvent.pageY;
    scrollAcc.current += scrollY.current - y; // finger up = scroll down, like a touchpad
    scrollY.current = y;
    const notches = Math.trunc(scrollAcc.current / SCROLL_STEP_PX);
    if (notches !== 0) {
      scrollAcc.current -= notches * SCROLL_STEP_PX;
      p.send({ t: 'scroll', dy: notches });
      Haptics.selectionAsync();
    }
  };

  const hold = (b: Button) => ({
    onDown: () => {
      p.send({ t: 'button', b, down: true });
      Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    },
    onUp: () => p.send({ t: 'button', b, down: false }),
  });

  const always = p.settings.mode === 'always';
  const title = always ? (pressed ? 'Paused' : 'Pointing') : pressed ? 'Pointing' : 'Hold to Point';
  const subtitle = always
    ? pressed
      ? 'Let go to keep pointing'
      : 'Touch and hold to pause · Tap to click'
    : pressed
      ? 'Turn your iPhone to move the pointer'
      : 'Tap to click';
  const pillLabel = connected
    ? p.macName || 'Mac'
    : p.status === 'connecting'
      ? 'Connecting…'
      : 'Not Connected';
  const pillIcon = p.kind === 'wifi' ? 'wifi' : p.kind === 'bluetooth' || p.kind === 'ble' || p.kind === 'hid' ? 'antenna.radiowaves.left.and.right' : undefined;

  const ringScale = ring.interpolate({ inputRange: [0, 1], outputRange: [0.6, 1.6] });
  const ringOpacity = ring.interpolate({ inputRange: [0, 0.2, 1], outputRange: [0, 0.55, 0] });
  const onAurora = pressed;

  return (
    <View style={[styles.root, { paddingTop: insets.top + space.sm, paddingBottom: typing && kbHeight > 0 ? kbHeight + space.sm : insets.bottom + TAB_BAR_SPACE }]}>
      <View style={styles.top}>
        <GlassCircle
          icon="target"
          label={p.practiceRunning ? 'Stop Practice' : 'Practice Clicking'}
          active={p.practiceRunning}
          disabled={!connected}
          onPress={() => p.onPractice(!p.practiceRunning)}
        />
        <View ref={tPill} collapsable={false} style={styles.pill}>
        <StatusPill label={pillLabel} color={paletteStatusColor(c, p.status)} pulse={p.status === 'connecting'} icon={connected ? pillIcon : undefined} onPress={p.onOpenConnect} />
        </View>
        <GlassCircle icon="keyboard" label={typing ? 'Hide Keyboard' : 'Keyboard'} active={typing} disabled={!connected} onPress={() => p.onKeyboard(!typing)} />
      </View>
      {p.warning && !typing ? <WarningRow text={p.warning.text} onPress={p.warning.onPress} /> : null}
      {p.practiceRunning ? (
        <View style={[styles.banner, { backgroundColor: c.card }]} accessibilityLiveRegion="polite">
          <Icon name="target" size={18} color={c.tint} weight="semibold" />
          <T v="footnote" weight="500" style={styles.flex}>
            Practice running on Mac: point and tap to click
          </T>
          <Pressable hitSlop={8} onPress={() => p.onPractice(false)} accessibilityRole="button" accessibilityLabel="Stop Practice">
            <T v="subhead" weight="600" color={c.tint}>
              Stop
            </T>
          </Pressable>
        </View>
      ) : null}
      {!typing ? (
        <SegmentedControl<PointerMode>
          options={[
            { key: 'hold', label: 'Hold to Point' },
            { key: 'always', label: 'Always On' },
          ]}
          value={p.settings.mode}
          onChange={p.onModeChange}
        />
      ) : null}

      <View style={styles.padRow}>
        <View
          ref={tPad}
          style={[styles.pad, { backgroundColor: c.card }, pressed && styles.padGlow]}
          onTouchStart={padStart}
          onTouchEnd={padEnd}
          onTouchCancel={padCancel}
          accessible
          onAccessibilityTap={() => click('left')}
          accessibilityRole="button"
          accessibilityLabel={title}
          accessibilityHint={subtitle}
        >
          <Animated.View style={[StyleSheet.absoluteFill, { opacity: glow }]} pointerEvents="none">
            <LinearGradient colors={aurora.colors} start={aurora.start} end={aurora.end} style={[StyleSheet.absoluteFill, styles.padRadius]} />
          </Animated.View>
          <View style={styles.padCenter} pointerEvents="box-none">
            <View style={styles.iconWrap}>
              <Animated.View style={[styles.ring, { borderColor: '#FFFFFF', opacity: ringOpacity, transform: [{ scale: ringScale }] }]} />
              <View style={[styles.iconDisc, { backgroundColor: onAurora ? 'rgba(255,255,255,0.22)' : c.fill }]}>
                <Icon name={pressed ? 'cursorarrow.motionlines' : 'hand.point.up.left.fill'} size={34} color={onAurora ? '#FFFFFF' : c.tint} />
              </View>
            </View>
            <T v="title2" color={onAurora ? '#FFFFFF' : c.label} center>
              {title}
            </T>
            <T v="subhead" color={onAurora ? 'rgba(255,255,255,0.85)' : c.secondaryLabel} center style={{ maxWidth: 230 }}>
              {subtitle}
            </T>
            {!connected && !pressed && !typing ? (
              <View pointerEvents="box-none" style={{ marginTop: space.md, alignSelf: 'stretch', paddingHorizontal: space.xxl }}>
                <PrimaryButton title="Connect to a Mac" icon="laptopcomputer" onPress={p.onOpenConnect} />
              </View>
            ) : null}
            {p.gyroAvailable === false && !pressed ? (
              <T v="footnote" color={c.secondaryLabel} center style={{ marginTop: space.sm }}>
                Motion sensors aren’t available on this device.
              </T>
            ) : null}
          </View>
        </View>

        <View
          ref={tScroll}
          style={[styles.scroll, { backgroundColor: scrolling ? c.fillStrong : c.card }]}
          onStartShouldSetResponder={() => true}
          onResponderGrant={scrollGrant}
          onResponderMove={scrollMove}
          onResponderRelease={() => setScrolling(false)}
          onResponderTerminate={() => setScrolling(false)}
          onResponderTerminationRequest={() => false}
          accessibilityLabel="Scroll"
          accessibilityHint="Drag up or down to scroll"
        >
          <Icon name="chevron.up" size={16} color={c.secondaryLabel} weight="bold" />
          <View style={styles.grip}>
            {[0, 1, 2, 3, 4].map((i) => (
              <View key={i} style={[styles.gripLine, { backgroundColor: c.tertiaryLabel }]} />
            ))}
          </View>
          <T v="caption" color={c.secondaryLabel} weight="600">
            Scroll
          </T>
          <View style={styles.grip}>
            {[0, 1, 2, 3, 4].map((i) => (
              <View key={i} style={[styles.gripLine, { backgroundColor: c.tertiaryLabel }]} />
            ))}
          </View>
          <Icon name="chevron.down" size={16} color={c.secondaryLabel} weight="bold" />
        </View>
      </View>

      <View style={styles.row} ref={tClicks} collapsable={false}>
        <HoldButton icon="computermouse.fill" label="Left Click" {...hold('left')} style={styles.click} />
        <HoldButton icon="contextualmenu.and.cursorarrow" label="Right Click" {...hold('right')} style={styles.click} />
      </View>
      {typing ? (
        <KeyboardPanel send={p.send} onTyped={p.onTyped} onDone={() => p.onKeyboard(false)} fieldId={p.keyboardField} />
      ) : (
      <View style={styles.row}>
        <View ref={tCenter} collapsable={false} style={styles.flex}>
          <IconButton icon="dot.circle.and.cursorarrow" label="Center" onPress={() => { p.send({ t: 'center' }); Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); }} />
        </View>
        <View ref={tCalib} collapsable={false} style={styles.flex}>
          <IconButton icon="scope" label="Calibrate" onPress={p.onCalibrate} />
        </View>
        <IconButton icon="backward.fill" label="Previous" accessibilityLabel="Previous Slide" onPress={() => { p.send({ t: 'key', k: 'left' }); Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); }} style={styles.flex} />
        <IconButton icon="forward.fill" label="Next" accessibilityLabel="Next Slide" onPress={() => { p.send({ t: 'key', k: 'right' }); Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light); }} style={styles.flex} />
      </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, paddingHorizontal: space.lg, gap: space.md },
  top: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: space.sm, paddingBottom: space.xs },
  pill: { flexShrink: 1, alignItems: 'center' },
  circle: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  banner: { flexDirection: 'row', alignItems: 'center', gap: space.sm, paddingHorizontal: space.lg, paddingVertical: space.md, borderRadius: radius.card, borderCurve: 'continuous' },
  padRow: { flex: 1, flexDirection: 'row', gap: space.md },
  pad: { flex: 1, borderRadius: radius.surface, borderCurve: 'continuous', overflow: 'visible' },
  padRadius: { borderRadius: radius.surface, borderCurve: 'continuous' },
  padGlow: { shadowColor: '#5E5CE6', shadowOpacity: 0.55, shadowRadius: 28, shadowOffset: { width: 0, height: 8 } },
  padCenter: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: space.sm, padding: space.lg },
  iconWrap: { width: 112, height: 112, alignItems: 'center', justifyContent: 'center', marginBottom: space.sm },
  ring: { position: 'absolute', width: 112, height: 112, borderRadius: 56, borderWidth: 2 },
  iconDisc: { width: 80, height: 80, borderRadius: 40, alignItems: 'center', justifyContent: 'center' },
  scroll: { width: 62, borderRadius: radius.surface, borderCurve: 'continuous', alignItems: 'center', justifyContent: 'space-between', paddingVertical: space.lg },
  grip: { gap: 5, alignItems: 'center' },
  gripLine: { width: 18, height: 3, borderRadius: 1.5 },
  row: { flexDirection: 'row', gap: space.md },
  click: { flex: 1 },
  flex: { flex: 1 },
});
