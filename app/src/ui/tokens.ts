import { createContext, createElement, useContext, useEffect, useState, type ReactNode } from 'react';
import { AccessibilityInfo, Platform, useColorScheme, type TextStyle } from 'react-native';

// Design tokens, docs/spec-v3.md section 1. Neutrals are the iOS system colours
// (hex values so they also work inside SVG and gradients).

export type Palette = {
  dark: boolean;
  background: string; // systemBackground
  grouped: string; // systemGroupedBackground
  card: string; // secondarySystemGroupedBackground
  cardRaised: string; // tertiarySystemGroupedBackground
  label: string;
  secondaryLabel: string;
  tertiaryLabel: string;
  separator: string;
  fill: string; // tertiarySystemFill
  fillStrong: string; // secondarySystemFill
  tint: string; // systemBlue
  success: string;
  warning: string;
  error: string;
  errorText: string; // error colour tuned for text contrast
  axisX: string;
  axisY: string;
  axisZ: string;
  onTint: string;
};

const light: Palette = {
  dark: false,
  background: '#FFFFFF',
  grouped: '#F2F2F7',
  card: '#FFFFFF',
  cardRaised: '#F2F2F7',
  label: '#000000',
  secondaryLabel: 'rgba(60,60,67,0.6)',
  tertiaryLabel: 'rgba(60,60,67,0.3)',
  separator: 'rgba(60,60,67,0.29)',
  fill: 'rgba(118,118,128,0.12)',
  fillStrong: 'rgba(120,120,128,0.16)',
  tint: '#007AFF',
  success: '#30D158',
  warning: '#FF9F0A',
  error: '#FF453A',
  errorText: '#D70015',
  axisX: '#FF3B30',
  axisY: '#28A745',
  axisZ: '#007AFF',
  onTint: '#FFFFFF',
};

export const dark: Palette = {
  dark: true,
  background: '#000000',
  grouped: '#000000',
  card: '#1C1C1E',
  cardRaised: '#2C2C2E',
  label: '#FFFFFF',
  secondaryLabel: 'rgba(235,235,245,0.6)',
  tertiaryLabel: 'rgba(235,235,245,0.3)',
  separator: 'rgba(84,84,88,0.6)',
  fill: 'rgba(118,118,128,0.24)',
  fillStrong: 'rgba(120,120,128,0.32)',
  tint: '#0A84FF',
  success: '#30D158',
  warning: '#FF9F0A',
  error: '#FF453A',
  errorText: '#FF6961',
  axisX: '#FF453A',
  axisY: '#30D158',
  axisZ: '#0A84FF',
  onTint: '#FFFFFF',
};

// Screens drawn on a fixed dark background (Welcome, Setup) force the dark
// palette so text stays light even when the phone is in Light Mode.
const SchemeOverride = createContext<'dark' | 'light' | null>(null);

export function ForceDark(p: { children: ReactNode }) {
  return createElement(SchemeOverride.Provider, { value: 'dark' }, p.children);
}

export function usePalette(): Palette {
  const forced = useContext(SchemeOverride);
  const system = useColorScheme();
  return (forced ?? system) === 'dark' ? dark : light;
}

// Brand gradient "Aurora", 135° (top-left to bottom-right).
export const aurora = {
  colors: ['#0A84FF', '#5E5CE6', '#BF5AF2'] as const,
  start: { x: 0, y: 0 },
  end: { x: 1, y: 1 },
};

export const glow = { core: '#64D2FF', outer: '#0A84FF' };

export const radius = { card: 22, button: 14, control: 10, surface: 28 };
export const space = { xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 24, xxxl: 32, margin: 20 };

const rounded = Platform.OS === 'ios' ? 'ui-rounded' : undefined;

// Type scale (pt). `rounded` = SF Pro Rounded for numbers and big values.
export const type = {
  largeTitle: { fontSize: 34, lineHeight: 41, fontWeight: '700', letterSpacing: 0.4 },
  title: { fontSize: 28, lineHeight: 34, fontWeight: '700', letterSpacing: 0.36 },
  title2: { fontSize: 22, lineHeight: 28, fontWeight: '600', letterSpacing: -0.26 },
  headline: { fontSize: 17, lineHeight: 22, fontWeight: '600', letterSpacing: -0.43 },
  body: { fontSize: 17, lineHeight: 22, fontWeight: '400', letterSpacing: -0.43 },
  callout: { fontSize: 16, lineHeight: 21, fontWeight: '400', letterSpacing: -0.31 },
  subhead: { fontSize: 15, lineHeight: 20, fontWeight: '400', letterSpacing: -0.23 },
  footnote: { fontSize: 13, lineHeight: 18, fontWeight: '400', letterSpacing: -0.08 },
  caption: { fontSize: 12, lineHeight: 16, fontWeight: '400', letterSpacing: 0 },
} satisfies Record<string, TextStyle>;

export const roundedFont: TextStyle = rounded ? { fontFamily: rounded } : {};
export const tabular: TextStyle = { fontVariant: ['tabular-nums'] };

// Springs (spec: response ~0.35-0.5 s, damping ~0.8) for RN Animated.spring.
export const spring = { damping: 18, stiffness: 180, mass: 1 };

export function useReduceMotion(): boolean {
  const [reduce, setReduce] = useState(false);
  useEffect(() => {
    let alive = true;
    AccessibilityInfo.isReduceMotionEnabled().then((v) => alive && setReduce(v)).catch(() => {});
    const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduce);
    return () => {
      alive = false;
      sub.remove();
    };
  }, []);
  return reduce;
}
