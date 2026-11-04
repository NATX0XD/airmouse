import { useEffect } from 'react';
import { Animated, StyleSheet, useAnimatedValue } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Icon, T, type SymbolName } from './components';
import { usePalette, useReduceMotion } from './tokens';

// Small capsule at the top ("Calibrated"). `id` changes = show again.
export function Toast(p: { id: number; text: string; icon?: SymbolName; iconColor?: string; durationMs?: number; onHidden: () => void }) {
  const c = usePalette();
  const insets = useSafeAreaInsets();
  const reduceMotion = useReduceMotion();
  const v = useAnimatedValue(0);
  const { id, onHidden } = p;
  const hold = p.durationMs ?? 1800;

  useEffect(() => {
    if (!id) return;
    v.setValue(0);
    const anim = Animated.sequence([
      Animated.spring(v, { toValue: 1, useNativeDriver: true, damping: 18, stiffness: 220 }),
      Animated.delay(hold),
      Animated.timing(v, { toValue: 0, duration: 260, useNativeDriver: true }),
    ]);
    anim.start(({ finished }) => finished && onHidden());
    return () => anim.stop();
  }, [id, v, onHidden, hold]);

  if (!id) return null;
  const translateY = v.interpolate({ inputRange: [0, 1], outputRange: [reduceMotion ? 0 : -24, 0] });
  return (
    <Animated.View
      pointerEvents="none"
      accessibilityLiveRegion="polite"
      style={[styles.toast, { top: insets.top + 6, opacity: v, transform: [{ translateY }], backgroundColor: c.dark ? c.cardRaised : c.card }]}
    >
      <Icon name={p.icon ?? 'checkmark.circle.fill'} size={18} color={p.iconColor ?? c.success} />
      <T v="subhead" weight="600">
        {p.text}
      </T>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  toast: {
    position: 'absolute',
    alignSelf: 'center',
    zIndex: 200,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 16,
    height: 40,
    borderRadius: 20,
    shadowColor: '#000',
    shadowOpacity: 0.18,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 6 },
  },
});
