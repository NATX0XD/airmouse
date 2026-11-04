import type { ComponentType } from 'react';
import type { StyleProp, ViewStyle } from 'react-native';
import { requireNativeViewManager, requireOptionalNativeModule } from 'expo-modules-core';

export type MotionHighlight = 'yaw' | 'pitch' | 'roll' | null;
type Props = { yaw: number; pitch: number; roll: number; highlight: MotionHighlight; dark: boolean; style?: StyleProp<ViewStyle> };

// SceneKit 3D phone (iOS only). null when this build has no native code, so callers can fall back to a 2D diagram.
function load(): ComponentType<Props> | null {
  try {
    if (!requireOptionalNativeModule('AirMouseMotion')) return null;
    return requireNativeViewManager<Props>('AirMouseMotion');
  } catch {
    return null;
  }
}

export const AirMouseMotionView = load();
