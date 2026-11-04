import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode, type RefObject } from 'react';
import { Animated, Pressable, StyleSheet, View, useAnimatedValue, useWindowDimensions, type HostInstance } from 'react-native';
import Svg, { Defs, Mask, Rect } from 'react-native-svg';
import * as Haptics from 'expo-haptics';
import { calloutPlacement, TOUR, type Rect as Frame, type Tour, type TourTarget } from '../setup/onboarding';
import { PrimaryButton, T } from './components';
import { radius, space, usePalette, useReduceMotion } from './tokens';

const AnimatedRect = Animated.createAnimatedComponent(Rect);

type Registry = { register: (id: TourTarget, ref: RefObject<HostInstance | null>) => () => void; get: (id: TourTarget) => RefObject<HostInstance | null> | undefined };
const Ctx = createContext<Registry | null>(null);

export function TourProvider({ children }: { children: ReactNode }) {
  const map = useRef(new Map<TourTarget, RefObject<HostInstance | null>>());
  const value = useMemo<Registry>(
    () => ({
      register: (id, ref) => {
        map.current.set(id, ref);
        return () => {
          if (map.current.get(id) === ref) map.current.delete(id);
        };
      },
      get: (id) => map.current.get(id),
    }),
    [],
  );
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

// Attach the returned ref to a View (collapsable={false}) to make it a tour target.
export function useTourTarget(id: TourTarget) {
  const ref = useRef<HostInstance>(null);
  const ctx = useContext(Ctx);
  useEffect(() => ctx?.register(id, ref), [ctx, id]);
  return ref;
}

const PAD = 8;
const CALLOUT_H = 168;

// Dims the screen, cuts a rounded spotlight around the current target and
// shows a callout. Spring-animates between targets.
export function TourOverlay(p: { tour: Tour; onNext: () => void; onSkip: () => void }) {
  const c = usePalette();
  const ctx = useContext(Ctx);
  const reduceMotion = useReduceMotion();
  const { width, height } = useWindowDimensions();
  const [frame, setFrame] = useState<Frame | null>(null);
  const x = useAnimatedValue(width / 2);
  const y = useAnimatedValue(height / 2);
  const w = useAnimatedValue(0);
  const h = useAnimatedValue(0);
  const r = useAnimatedValue(18);
  const show = useAnimatedValue(0);
  const step = TOUR[p.tour.index];

  const measure = useCallback(() => {
    const ref = ctx?.get(step.target);
    ref?.current?.measureInWindow((mx, my, mw, mh) => {
      if (mw > 0 && mh > 0) setFrame({ x: mx - PAD, y: my - PAD, w: mw + PAD * 2, h: mh + PAD * 2 });
    });
  }, [ctx, step.target]);

  useEffect(() => {
    if (!p.tour.active) return;
    const id = setTimeout(measure, 60); // let layout settle (tab switch, fonts)
    return () => clearTimeout(id);
  }, [p.tour.active, p.tour.index, measure]);

  useEffect(() => {
    Animated.timing(show, { toValue: p.tour.active ? 1 : 0, duration: 220, useNativeDriver: false }).start();
  }, [p.tour.active, show]);

  useEffect(() => {
    if (!frame) return;
    const corner = Math.min(frame.h / 2, 26);
    const go = (v: Animated.Value, to: number) =>
      reduceMotion ? Animated.timing(v, { toValue: to, duration: 0, useNativeDriver: false }) : Animated.spring(v, { toValue: to, useNativeDriver: false, damping: 20, stiffness: 170 });
    Animated.parallel([go(x, frame.x), go(y, frame.y), go(w, frame.w), go(h, frame.h), go(r, corner)]).start();
  }, [frame, reduceMotion, x, y, w, h, r]);

  if (!p.tour.active) return null;
  const place = frame ? calloutPlacement(frame, height, CALLOUT_H) : { top: height / 2 - CALLOUT_H / 2, below: true };
  const last = p.tour.index === TOUR.length - 1;
  const next = () => {
    Haptics.selectionAsync();
    p.onNext();
  };

  return (
    <Animated.View style={[StyleSheet.absoluteFill, { opacity: show, zIndex: 100 }]}>
      <Pressable style={StyleSheet.absoluteFill} onPress={next} accessibilityLabel="Next tip">
        <Svg width={width} height={height}>
          <Defs>
            <Mask id="spot" x={0} y={0} width={width} height={height} maskUnits="userSpaceOnUse">
              <Rect x={0} y={0} width={width} height={height} fill="#FFFFFF" />
              <AnimatedRect x={x} y={y} width={w} height={h} rx={r} ry={r} fill="#000000" />
            </Mask>
          </Defs>
          <Rect x={0} y={0} width={width} height={height} fill="rgba(0,0,0,0.62)" mask="url(#spot)" />
          <AnimatedRect x={x} y={y} width={w} height={h} rx={r} ry={r} fill="none" stroke="rgba(255,255,255,0.9)" strokeWidth={2} />
        </Svg>
      </Pressable>
      <View style={[styles.callout, { top: place.top, backgroundColor: c.dark ? c.cardRaised : c.card }]}>
        <View style={styles.calloutHead}>
          <T v="headline">{step.title}</T>
          <T v="footnote" color={c.secondaryLabel} rounded>
            {p.tour.index + 1} of {TOUR.length}
          </T>
        </View>
        <T v="subhead" color={c.secondaryLabel}>
          {step.body}
        </T>
        <View style={styles.calloutActions}>
          <Pressable onPress={p.onSkip} hitSlop={10} accessibilityRole="button" accessibilityLabel="Skip Tour">
            <T v="subhead" weight="600" color={c.secondaryLabel}>
              Skip Tour
            </T>
          </Pressable>
          <PrimaryButton title={last ? 'Done' : 'Next'} onPress={next} style={{ minWidth: 112 }} compact />
        </View>
      </View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  callout: {
    position: 'absolute',
    left: space.margin,
    right: space.margin,
    borderRadius: radius.card,
    borderCurve: 'continuous',
    padding: space.lg,
    gap: 6,
    shadowColor: '#000',
    shadowOpacity: 0.25,
    shadowRadius: 24,
    shadowOffset: { width: 0, height: 10 },
  },
  calloutHead: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  calloutActions: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginTop: space.sm },
});
