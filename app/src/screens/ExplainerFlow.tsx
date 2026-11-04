import { useEffect, useState } from 'react';
import { Accelerometer } from 'expo-sensors';
import { Animated, Image, Modal, PanResponder, Pressable, ScrollView, StyleSheet, View, useAnimatedValue, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PrimaryButton, Icon, T } from '../ui/components';
import { space, usePalette, useReduceMotion } from '../ui/tokens';
import type { GyroSample } from '../motion/engine';

type Props = { visible: boolean; onDone: () => void; addGyroListener?: (cb: (sample: GyroSample) => void) => () => void };
type Step = { title: string; body: string; fact?: string; image: ReturnType<typeof require> };

const SENSOR_CARDS = [
  ['Gyroscope', 'The main one: measures how fast your phone turns, 100 times a second. Turn left or right to move sideways; tilt up or down to move vertically.', require('../../assets/illustrations/explainer/sensors/gyroscope.png')],
  ['Accelerometer', 'Feels gravity, so AirMouse knows whether the phone is upright. Calibration uses it to check the phone is flat against the screen.', require('../../assets/illustrations/explainer/sensors/accelerometer.png')],
  ['Proximity sensor', 'The sensor next to the front camera. It confirms the phone is touching the monitor, so calibration cannot start by mistake.', require('../../assets/illustrations/explainer/sensors/proximity.png')],
  ['Touchscreen', 'Hold the pad to point, tap to click, plus buttons for right click, scrolling and typing.', require('../../assets/illustrations/explainer/sensors/touchscreen.png')],
] as const;

const STEPS: Step[] = [
  { title: 'Sensors AirMouse Uses', body: "No extra hardware. Just what's already inside your iPhone.", image: require('../../assets/illustrations/explainer/sensors/gyroscope.png') },
  { title: 'Your iPhone feels movement.', body: 'Inside your iPhone is a tiny motion sensor called a gyroscope. It notices when you turn or tilt the phone.', image: require('../../assets/illustrations/explainer/01-gyro.png') },
  { title: 'It checks 100 times a second.', body: 'Every hundredth of a second, AirMouse asks the sensor: “How fast are you turning right now?”', fact: 'That is faster than a blink.', image: require('../../assets/illustrations/explainer/02-sampling.png') },
  { title: 'Turning becomes moving.', body: 'Turn left or right and the pointer moves sideways. Tilt up or down and it moves up or down.', image: require('../../assets/illustrations/explainer/03-direction.png') },
  { title: 'Smoothing out shaky hands.', body: "Everyone's hands shake a little. AirMouse filters out tiny wobbles, so the pointer stays steady but still follows quick moves.", image: require('../../assets/illustrations/explainer/04-smoothing.png') },
  { title: 'Sending it to your Mac.', body: 'The phone sends small messages (“move 3 dots right”) over Wi-Fi or Bluetooth. Nothing leaves your home network.', image: require('../../assets/illustrations/explainer/05-sending.png') },
  { title: 'Your Mac moves the pointer.', body: "The AirMouse app on your Mac receives each message and moves the cursor smoothly at your screen's refresh rate.", image: require('../../assets/illustrations/explainer/06-mac-cursor.png') },
  { title: 'Calibration makes it accurate.', body: 'By pointing at 5 dots, AirMouse learns how far the cursor should move when you turn, for your screen and your distance.', image: require('../../assets/illustrations/explainer/07-calibration.png') },
  { title: 'Touch to point, tap to click.', body: 'Hold the touch pad to move, tap to click, and use the buttons for right click and scrolling.', image: require('../../assets/illustrations/explainer/08-touch-click.png') },
];

export function ExplainerFlow({ visible, onDone, addGyroListener }: Props) {
  const c = usePalette();
  const insets = useSafeAreaInsets();
  const reduceMotion = useReduceMotion();
  const { width } = useWindowDimensions();
  const [index, setIndex] = useState(0);
  const [gyro, setGyro] = useState<GyroSample | null>(null);
  const [accel, setAccel] = useState<{ x: number; y: number; z: number } | null>(null);
  const enter = useAnimatedValue(1);
  const step = STEPS[index];
  const close = () => { setIndex(0); onDone(); };
  const next = () => index === STEPS.length - 1 ? close() : setIndex((n) => n + 1);
  const back = () => setIndex((n) => Math.max(0, n - 1));

  useEffect(() => {
    enter.setValue(0);
    Animated.timing(enter, { toValue: 1, duration: reduceMotion ? 0 : 240, useNativeDriver: true }).start();
  }, [index, enter, reduceMotion]);
  useEffect(() => {
    if (!visible || !addGyroListener || (index !== 1 && index !== 2)) return;
    return addGyroListener(setGyro);
  }, [visible, index, addGyroListener]);
  useEffect(() => {
    if (!visible || index !== 0) return;
    Accelerometer.setUpdateInterval(100);
    const sub = Accelerometer.addListener(setAccel);
    return () => sub.remove();
  }, [visible, index]);

  const responder = PanResponder.create({
    onMoveShouldSetPanResponder: (_, g) => Math.abs(g.dx) > 12 && Math.abs(g.dx) > Math.abs(g.dy),
    onPanResponderRelease: (_, g) => { if (g.dx < -50) next(); else if (g.dx > 50) back(); },
  });
  const translateX = enter.interpolate({ inputRange: [0, 1], outputRange: [reduceMotion ? 0 : 18, 0] });
  const art = Math.min(width - space.margin * 2, 360);

  return <Modal visible={visible} animationType="fade" presentationStyle="fullScreen" onRequestClose={close}>
    <View style={[styles.root, { backgroundColor: c.grouped, paddingTop: insets.top + space.sm, paddingBottom: insets.bottom + space.lg }]}>
      <View style={styles.header}>
        <Pressable onPress={back} disabled={index === 0} style={[styles.back, index === 0 && { opacity: 0 }]} accessibilityLabel="Back"><Icon name="chevron.left" size={17} color={c.tint} /><T color={c.tint}>Back</T></Pressable>
        <View style={styles.dots}>{STEPS.map((s, i) => <View key={s.title} style={[styles.dot, { width: i === index ? 22 : 7, backgroundColor: i === index ? c.tint : c.fillStrong }]} />)}</View>
        <Pressable onPress={close} hitSlop={12}><T color={c.secondaryLabel}>Skip</T></Pressable>
      </View>
      <Animated.View {...responder.panHandlers} style={[styles.stage, { opacity: enter, transform: [{ translateX }] }]}> 
        {index === 0 ? <ScrollView contentContainerStyle={styles.sensorOverview} showsVerticalScrollIndicator={false}>
          <View style={styles.copy}><T v="title" center>{step.title}</T><T v="body" color={c.secondaryLabel} center style={styles.body}>{step.body}</T></View>
          <View style={styles.sensorGrid}>{SENSOR_CARDS.map(([name, body, image]) => <View key={name} style={[styles.sensorCard, { backgroundColor: c.card, borderColor: c.separator }]}><Image source={image} style={styles.sensorImage} resizeMode="contain" /><T v="subhead" weight="600">{name}</T><T v="caption" color={c.secondaryLabel} style={styles.sensorBody}>{body}</T></View>)}</View>
          <View style={[styles.also, { borderColor: c.separator }]}><T v="caption" color={c.secondaryLabel}>Also used</T><T v="caption"><T weight="600">Camera</T> · scans the QR code to pair　 <T weight="600">Haptics</T> · gentle feedback</T></View>
          <View style={[styles.liveSmall, { backgroundColor: c.card, borderColor: c.separator }]}><T v="caption" color={c.secondaryLabel}>Live accelerometer tilt</T><T v="subhead" weight="600">{accel ? `x ${accel.x.toFixed(2)} · y ${accel.y.toFixed(2)} · z ${accel.z.toFixed(2)}` : 'Reading…'}</T></View>
        </ScrollView> : <>
          <Image source={step.image} style={{ width: art, height: art * 0.72 }} resizeMode="contain" />
          <View style={styles.copy}><T v="title" center>{step.title}</T><T v="body" color={c.secondaryLabel} center style={styles.body}>{step.body}</T>{step.fact ? <T v="footnote" color={c.tint} center style={styles.fact}>Fun fact · {step.fact}</T> : null}</View>
          {(index === 2 || index === 3) && addGyroListener ? <View style={[styles.live, { backgroundColor: c.card, borderColor: c.separator }]}><View style={[styles.liveDot, { left: 50 + Math.max(-42, Math.min(42, (gyro?.x ?? 0) * 90)), top: 50 + Math.max(-42, Math.min(42, (gyro?.z ?? 0) * 90)) }]} /><T v="caption" color={c.secondaryLabel}>Live sensor dot</T></View> : null}
        </>}
      </Animated.View>
      <PrimaryButton title={index === STEPS.length - 1 ? 'Done' : 'Next'} onPress={next} />
    </View>
  </Modal>;
}

const styles = StyleSheet.create({ root: { flex: 1, paddingHorizontal: space.margin }, header: { height: 44, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }, back: { flexDirection: 'row', alignItems: 'center', gap: 4, minWidth: 70 }, dots: { flexDirection: 'row', gap: 5, alignItems: 'center' }, dot: { height: 7, borderRadius: 4 }, stage: { flex: 1, alignItems: 'center', justifyContent: 'center' }, sensorOverview: { alignItems: 'center', paddingVertical: space.md, gap: space.md }, sensorGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: space.sm, justifyContent: 'center' }, sensorCard: { width: '47%', minHeight: 190, borderRadius: 16, borderWidth: 1, padding: 10, gap: 4 }, sensorImage: { width: '100%', height: 92 }, sensorBody: { lineHeight: 16 }, also: { width: '100%', borderTopWidth: 1, paddingTop: space.sm, gap: 3 }, liveSmall: { borderWidth: 1, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 8, alignItems: 'center', gap: 2 }, copy: { alignItems: 'center', gap: space.sm }, body: { maxWidth: 350 }, fact: { marginTop: space.xs }, live: { width: 110, height: 110, borderRadius: 55, borderWidth: 1, alignItems: 'center', justifyContent: 'flex-end', paddingBottom: 10 }, liveDot: { position: 'absolute', width: 12, height: 12, marginLeft: -6, marginTop: -6, borderRadius: 6, backgroundColor: '#0A84FF', shadowColor: '#0A84FF', shadowOpacity: 0.8, shadowRadius: 9 } });
