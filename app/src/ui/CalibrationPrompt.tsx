import { Modal, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Icon, Material, PrimaryButton, SecondaryButton, T, type SymbolName } from './components';
import { aurora, radius, space, usePalette } from './tokens';

const ROWS: { icon: SymbolName; text: string }[] = [
  { icon: 'iphone.gen3', text: 'Hold iPhone against the screen' },
  { icon: 'scope', text: 'Point at 5 dots' },
  { icon: 'checkmark.circle', text: 'Check and done' },
];

// Centred glass popup over a dimmed backdrop, shown right after connecting
// to a display that has no 5-point calibration yet (docs/spec-v3.md 4a.5).
export function CalibrationPrompt(p: { visible: boolean; onStart: () => void; onLater: () => void }) {
  const c = usePalette();
  return (
    <Modal visible={p.visible} transparent animationType="fade" statusBarTranslucent onRequestClose={p.onLater}>
      <View style={styles.backdrop}>
        <Material style={styles.card}>
          <View style={styles.head}>
            <LinearGradient colors={aurora.colors} start={aurora.start} end={aurora.end} style={styles.badge}>
              <Icon name="scope" size={30} color="#FFFFFF" weight="semibold" />
            </LinearGradient>
            <T v="title2" center>
              Calibrate for Accurate Pointing
            </T>
          </View>
          <View style={styles.rows}>
            {ROWS.map((row) => (
              <View key={row.text} style={styles.row}>
                <Icon name={row.icon} size={20} color={c.tint} weight="medium" style={styles.rowIcon} />
                <T v="callout">{row.text}</T>
              </View>
            ))}
          </View>
          <View style={styles.buttons}>
            <PrimaryButton title="Start Calibration" icon="scope" onPress={p.onStart} />
            <SecondaryButton title="Later" plain onPress={p.onLater} />
          </View>
        </Material>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.38)', alignItems: 'center', justifyContent: 'center', padding: space.xxl },
  card: { alignSelf: 'stretch', maxWidth: 360, borderRadius: radius.card + 6, borderCurve: 'continuous', padding: space.xxl, gap: space.xl, overflow: 'hidden' },
  head: { alignItems: 'center', gap: space.md },
  badge: { width: 60, height: 60, borderRadius: 16, borderCurve: 'continuous', alignItems: 'center', justifyContent: 'center' },
  rows: { gap: space.md, alignSelf: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', gap: space.md },
  rowIcon: { width: 28 },
  buttons: { gap: space.xs },
});
