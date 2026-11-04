import { useEffect, useState } from 'react';
import { Animated, Modal, Pressable, StyleSheet, View, useAnimatedValue, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { pagerBack, pagerNext, WELCOME_PAGES, type Pager } from '../setup/onboarding';
import { LinearGradient } from 'expo-linear-gradient';
import { CIRCLE_GRADIENTS, Icon, IconCircle, Material, PrimaryButton, T, type CircleTone, type SymbolName } from '../ui/components';
import { Illustration } from '../ui/Illustration';
import { radius, space, usePalette, useReduceMotion } from '../ui/tokens';

type Props = { visible: boolean; startPage?: number; onDone: () => void };

export function WelcomeFlow(p: Props) {
  const c = usePalette();
  const insets = useSafeAreaInsets();
  const reduceMotion = useReduceMotion();
  const { width } = useWindowDimensions();
  const [pager, setPager] = useState<Pager>({ index: p.startPage ?? 0, done: false });
  const page = WELCOME_PAGES[pager.index];
  const enter = useAnimatedValue(1);
  useEffect(() => {
    enter.setValue(0);
    Animated.spring(enter, { toValue: 1, useNativeDriver: true, damping: 18, stiffness: 170 }).start();
  }, [pager.index, enter]);

  const next = () => {
    const n = pagerNext(pager, WELCOME_PAGES.length);
    if (n.done) p.onDone();
    else setPager(n);
  };
  const artW = Math.min(width - space.margin * 2, 360);
  const translateX = enter.interpolate({ inputRange: [0, 1], outputRange: [reduceMotion ? 0 : 24, 0] });

  return (
    <Modal visible={p.visible} animationType="fade" presentationStyle="fullScreen" onRequestClose={p.onDone}>
      <LinearGradient colors={['#090B2A', '#24135A', '#100D36']} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={[styles.root, { paddingTop: insets.top + space.sm, paddingBottom: insets.bottom + space.lg }]}> 
        <View pointerEvents="none" style={[styles.orb, styles.orbBlue]} />
        <View pointerEvents="none" style={[styles.orb, styles.orbPurple]} />
        <View style={styles.header}>
          <Pressable
            onPress={() => setPager(pagerBack(pager))}
            disabled={pager.index === 0}
            hitSlop={12}
            style={[styles.back, pager.index === 0 && { opacity: 0 }]}
            accessibilityRole="button"
            accessibilityLabel="Back"
          >
            <Icon name="chevron.left" size={17} color={c.tint} weight="semibold" />
            <T color={c.tint}>Back</T>
          </Pressable>
          <View style={styles.dots}>
            {WELCOME_PAGES.map((k, i) => (
              <View key={k} style={[styles.dot, { width: i === pager.index ? 22 : 8, backgroundColor: i === pager.index ? c.tint : c.fillStrong }]} />
            ))}
          </View>
          <View style={{ minWidth: 70 }} />
        </View>

        <Animated.View style={[styles.stage, { opacity: enter, transform: [{ translateX }] }]}>
          {page === 'welcome' ? (
            <>
              <Illustration name="hero-pointing" width={artW} height={artW * 0.625} />
              <View style={styles.copy}>
                <T v="largeTitle" center>
                  Meet AirMouse
                </T>
                <T color="rgba(255,255,255,0.74)" center>
                  Your iPhone becomes a pointer for your Mac.
                </T>
              </View>
              <Material style={styles.glassCard}>
                <Point icon="cursorarrow.motionlines" tone="blue" title="Point to move" body="Turn your iPhone, the cursor follows." />
                <Point icon="hand.tap.fill" tone="purple" title="Tap to click" body="Tap the touch area, hold to drag." />
                <Point icon="wifi" tone="teal" title="Works over Wi-Fi or Bluetooth" body="No cables, no dongle." />
              </Material>
            </>
          ) : page === 'how' ? (
            <>
              <View style={styles.copy}>
                <T v="largeTitle" center>
                  How It Works
                </T>
                <T color="rgba(255,255,255,0.74)" center style={{ maxWidth: 320 }}>
                  Three steps, about a hundred times a second.
                </T>
              </View>
              <Material style={[styles.glassCard, { paddingVertical: space.xl }]}> 
                <Illustration name="how-it-works" width={artW - space.xl * 2} height={130} />
              </Material>
              <Material style={styles.glassCard}>
                <Point icon="gyroscope" tone="indigo" title="The gyroscope" body="measures how fast your hand turns, on three axes." />
                <Point icon="waveform.path" tone="blue" title="A One Euro filter" body="smooths out hand shake but stays quick when you move fast." />
                <Point icon="cursorarrow.rays" tone="purple" title="Your Mac" body="moves the real cursor, clicks and scrolls." />
              </Material>
            </>
          ) : (
            <>
              <Illustration name="get-mac" width={artW} height={artW * 0.625} />
              <View style={styles.copy}>
                <T v="largeTitle" center>
                  Get AirMouse for Mac
                </T>
                <T color="rgba(255,255,255,0.74)" center style={{ maxWidth: 320 }}>
                  Open AirMouse on your Mac. It shows a QR code to pair.
                </T>
              </View>
              <Material style={styles.glassCard}>
                <NumberedStep n={1} text="Install AirMouse on your Mac and open it." />
                <NumberedStep n={2} text="Allow Pointer Control when your Mac asks." />
                <NumberedStep n={3} text="Scan the QR code, or pick your Mac from the list." />
              </Material>
              <View style={[styles.linkSlot, { borderColor: c.separator }]}>
                <Icon name="link" size={15} color={c.secondaryLabel} />
                <T v="footnote" color={c.secondaryLabel}>
                  Download page coming soon
                </T>
              </View>
            </>
          )}
        </Animated.View>

        <PrimaryButton title={page === 'getMac' ? 'I Already Have It' : 'Continue'} onPress={next} />
      </LinearGradient>
    </Modal>
  );
}

function Point(p: { icon: SymbolName; tone: CircleTone; title: string; body: string }) {
  const c = usePalette();
  return (
    <View style={styles.point}>
      <IconCircle name={p.icon} tone={p.tone} size={40} />
      <View style={{ flex: 1 }}>
        <T v="headline">{p.title}</T>
        <T v="subhead" color={c.secondaryLabel}>
          {p.body}
        </T>
      </View>
    </View>
  );
}

function NumberedStep(p: { n: number; text: string }) {
  return (
    <View style={styles.point}>
      <LinearGradient colors={CIRCLE_GRADIENTS.aurora} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.num}>
        <T v="headline" color="#FFFFFF" rounded>
          {p.n}
        </T>
      </LinearGradient>
      <T v="callout" style={{ flex: 1 }}>
        {p.text}
      </T>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, paddingHorizontal: space.margin },
  header: { height: 44, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  back: { flexDirection: 'row', alignItems: 'center', gap: 4, minWidth: 70 },
  dots: { flexDirection: 'row', gap: 6, alignItems: 'center' },
  dot: { height: 8, borderRadius: 4 },
  stage: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: space.xl },
  copy: { gap: space.sm, alignItems: 'center' },
  card: { alignSelf: 'stretch', borderRadius: radius.card, borderCurve: 'continuous', padding: space.lg, gap: space.lg },
  glassCard: { alignSelf: 'stretch', borderRadius: radius.card, borderCurve: 'continuous', overflow: 'hidden', padding: space.lg, gap: space.lg, borderWidth: 1, borderColor: 'rgba(255,255,255,0.14)' },
  orb: { position: 'absolute', width: 260, height: 260, borderRadius: 130, opacity: 0.28 },
  orbBlue: { backgroundColor: '#0A84FF', top: -80, left: -120 },
  orbPurple: { backgroundColor: '#BF5AF2', bottom: 80, right: -120 },
  point: { flexDirection: 'row', alignItems: 'center', gap: space.md },
  num: { width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center', marginHorizontal: 3 },
  linkSlot: { flexDirection: 'row', alignItems: 'center', gap: 6, borderWidth: 1, borderStyle: 'dashed', borderRadius: 12, paddingHorizontal: 14, paddingVertical: 8 },
});
