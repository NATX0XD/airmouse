import { useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import appJson from '../../app.json';
import { DEFAULT_SETTINGS, type MotionSettings } from '../motion/engine';
import { DEFAULT_APP_SETTINGS, type AppSettings, type PointerMode, type TransportKind } from '../settings';
import type { TransportStatus } from '../transport/types';
import { Card, Icon, IconCircle, LargeTitle, ListRow, PrimaryButton, Section, SegmentedControl, SliderRow, SwitchRow, T, type CircleTone, type SymbolName } from '../ui/components';
import { roundedFont, space, usePalette } from '../ui/tokens';
import { TAB_BAR_SPACE } from '../ui/TabBar';
import { SENS_MAX, SENS_MIN, scaleSpeed } from '../motion/calibration';
import type { Diagnostics } from '../useAirMouse';

type Props = {
  settings: AppSettings;
  onChange: (s: AppSettings) => void;
  connectionLabel: string;
  connectionDetail?: string;
  screenFromMac: boolean;
  onOpenConnect: () => void;
  onCalibrate: () => void;
  onOpenSetup: () => void;
  missingCount: number;
  permissionsDone: number;
  status: TransportStatus;
  kind: TransportKind | null;
  macName: string;
  onShowTour: () => void;
  onShowWelcome: () => void;
  onShowExplainer: () => void;
  initialScroll?: number;
  diagnostics?: () => Diagnostics;
  onBench?: () => void;
};

export function SettingsScreen(props: Props) {
  const { settings, onChange, screenFromMac, onOpenConnect, onCalibrate, onOpenSetup, missingCount } = props;
  const c = usePalette();
  const insets = useSafeAreaInsets();
  const m = settings.motion;
  const setMotion = (patch: Partial<MotionSettings>) => onChange({ ...settings, motion: { ...m, ...patch } });
  const version = appJson.expo.version;

  return (
    <ScrollView
      contentContainerStyle={{ paddingTop: insets.top, paddingBottom: insets.bottom + TAB_BAR_SPACE + space.lg }}
      contentInsetAdjustmentBehavior="never"
      keyboardDismissMode="on-drag"
      contentOffset={props.initialScroll ? { x: 0, y: props.initialScroll } : undefined}
    >
      <LargeTitle title="Settings" />
      <View style={styles.body}>
        <StatusCard {...props} />
        <Section>
          <ListRow title="Change Mac…" icon="laptopcomputer" iconGradient chevron onPress={onOpenConnect} />
          <SwitchRow title="Reconnect Automatically" icon="arrow.triangle.2.circlepath" iconColor="#30B0C7" value={settings.autoConnect} onChange={(v) => onChange({ ...settings, autoConnect: v })} />
          <ListRow
            title="Permissions"
            icon="checkmark.shield.fill"
            iconColor={missingCount > 0 ? '#FF9F0A' : '#30D158'}
            value={`${props.permissionsDone}/4`}
            valueRounded
            chevron
            onPress={onOpenSetup}
          />
        </Section>

        <Section header="Pointer" footer={settings.mode === 'hold' ? 'The pointer moves only while your finger is on the touch area.' : 'The pointer always follows your iPhone. Touch and hold to pause.'}>
          <View style={styles.segmentRow}>
            <SegmentedControl<PointerMode>
              options={[
                { key: 'hold', label: 'Hold to Point' },
                { key: 'always', label: 'Always On' },
              ]}
              value={settings.mode}
              onChange={(mode) => onChange({ ...settings, mode })}
            />
          </View>
          <SliderRow
            title="Speed"
            value={m.sensitivity}
            min={SENS_MIN}
            max={SENS_MAX}
            step={50}
            format={(v) => `${Math.round(v)}`}
            minIcon="tortoise.fill"
            maxIcon="hare.fill"
            onCommit={(v) => setMotion(scaleSpeed(m, v))}
          />
          <SliderRow
            title="Acceleration"
            value={m.acceleration}
            min={0}
            max={1}
            step={0.05}
            format={(v) => (v === 0 ? 'Off' : `${Math.round(v * 100)}%`)}
            minLabel="Off"
            maxLabel="Strong"
            onCommit={(v) => setMotion({ acceleration: Number(v.toFixed(2)) })}
          />
          <SliderRow
            title="Smoothing"
            value={m.smoothing}
            min={0.25}
            max={5}
            step={0.25}
            format={(v) => (v <= 0.75 ? 'Smooth' : v >= 3 ? 'Responsive' : 'Balanced')}
            minLabel="Smoother"
            maxLabel="Faster"
            onCommit={(v) => setMotion({ smoothing: v })}
          />
          <SliderRow
            title="Steady Hand"
            value={m.deadzone}
            min={0}
            max={0.2}
            step={0.01}
            format={(v) => (v === 0 ? 'Off' : `${v.toFixed(2)} rad/s`)}
            minLabel="Off"
            maxLabel="Strong"
            onCommit={(v) => setMotion({ deadzone: Number(v.toFixed(2)) })}
          />
        </Section>

        <Section header="Gestures" footer="Flick your iPhone left or right, without touching the screen, to change slides.">
          <SwitchRow title="Flick to Change Slides" icon="hand.wave.fill" iconColor="#BF5AF2" value={settings.flickSlides} onChange={(v) => onChange({ ...settings, flickSlides: v })} />
        </Section>

        <Section header="Direction">
          <SwitchRow title="Invert Horizontal" icon="arrow.left.and.right" iconColor="#FF9F0A" value={m.invertX} onChange={(v) => setMotion({ invertX: v })} />
          <SwitchRow title="Invert Vertical" icon="arrow.up.and.down" iconColor="#FF9F0A" value={m.invertY} onChange={(v) => setMotion({ invertY: v })} />
        </Section>

        <Section header="Screen" footer={screenFromMac ? 'Set automatically by your Mac.' : 'Connect to a Mac to fill this in, or type the size in points.'}>
          <ScreenSize settings={settings} onChange={onChange} />
          {settings.screenName ? <ListRow title="Display" value={settings.screenName} /> : null}
          {settings.screenWMm > 0 ? <ListRow title="Physical Size" value={`${Math.round(settings.screenWMm)} × ${Math.round(settings.screenHMm)} mm`} valueRounded /> : null}
        </Section>

        <CalibrationSection settings={settings} onChange={onChange} onCalibrate={onCalibrate} />

        {props.diagnostics ? <DiagnosticsSection read={props.diagnostics} onBench={props.onBench} /> : null}

        <Section header="Help">
          <ListRow title="How AirMouse Works" icon="questionmark.circle" iconColor="#0A84FF" chevron onPress={props.onShowExplainer} />
          <ListRow title="Show Tour" icon="sparkles" iconColor="#BF5AF2" chevron onPress={props.onShowTour} />
          <ListRow title="Show Welcome" icon="hand.wave.fill" iconColor="#5E5CE6" chevron onPress={props.onShowWelcome} />
        </Section>

        <Section header="About">
          <ListRow title="Version" value={version} valueRounded />
          <ListRow title="Protocol" value="v3" valueRounded />
          <ListRow
            title="Reset All Settings"
            destructive
            onPress={() =>
              Alert.alert('Reset All Settings?', 'Your Mac, speed and calibration will be cleared.', [
                { text: 'Cancel', style: 'cancel' },
                { text: 'Reset', style: 'destructive', onPress: () => onChange(DEFAULT_APP_SETTINGS) },
              ])
            }
          />
        </Section>
        <T v="footnote" color={c.secondaryLabel} center>
          AirMouse turns your iPhone’s gyroscope into a pointer.
        </T>
      </View>
    </ScrollView>
  );
}

// Same layout as the Mac Home status card: device circle + state, then
// one row per transport.
function StatusCard(p: Props) {
  const c = usePalette();
  const connected = p.status === 'open';
  const viaWifi = connected && p.kind === 'wifi';
  const viaBt = connected && p.kind === 'bluetooth';
  const title = connected ? `Connected to ${p.macName || 'Mac'}` : p.status === 'connecting' ? `Connecting to ${p.macName || 'Mac'}…` : 'Not Connected';
  const sub = connected ? `${viaBt ? 'Bluetooth' : 'Wi-Fi'} · ${(p.connectionDetail ?? '').replace(/^Connected · /, '')}` : p.macName ? `Last connected: ${p.macName}` : 'Open AirMouse on your Mac to connect.';
  const dot = connected ? c.success : p.status === 'connecting' ? c.warning : c.tertiaryLabel;
  return (
    <Card style={{ gap: space.md }}>
      <View style={styles.statusHead}>
        <View style={[styles.statusHalo, { backgroundColor: connected ? 'rgba(48,209,88,0.16)' : c.fill }]}>
          <IconCircle name="laptopcomputer" tone="aurora" size={44} dot={dot} />
        </View>
        <View style={{ flex: 1 }}>
          <T v="headline" numberOfLines={2}>
            {title}
          </T>
          <T v="footnote" color={c.secondaryLabel} numberOfLines={1}>
            {sub}
          </T>
        </View>
      </View>
      <View style={[styles.hair, { backgroundColor: c.separator }]} />
      <TransportLine icon="wifi" color={viaWifi ? c.success : c.secondaryLabel} label="Wi-Fi" value={viaWifi ? 'Connected' : 'Not in use'} />
      <TransportLine icon="antenna.radiowaves.left.and.right" color={viaBt ? c.success : c.tint} label="Bluetooth" value={viaBt ? 'Connected' : 'Not in use'} />
    </Card>
  );
}

function TransportLine(p: { icon: SymbolName; color: string; label: string; value: string }) {
  const c = usePalette();
  return (
    <View style={styles.transport}>
      <Icon name={p.icon} size={17} color={p.color} weight="semibold" />
      <T v="subhead" weight="600" style={{ flex: 1 }}>
        {p.label}
      </T>
      <T v="subhead" color={c.secondaryLabel} numberOfLines={1}>
        {p.value}
      </T>
    </View>
  );
}

const CALIB_STEPS: { icon: SymbolName; tone: CircleTone; title: string; body: string }[] = [
  { icon: 'iphone', tone: 'aurora', title: '1. Hold your iPhone to the screen', body: 'Hold it still inside the glowing outline so AirMouse can measure the gyroscope’s drift.' },
  { icon: 'scope', tone: 'aurora', title: '2. Point at the left dot', body: 'Aim like a remote and tap your iPhone’s screen.' },
  { icon: 'arrow.left.and.right', tone: 'aurora', title: '3. Point at the right dot', body: 'Turn smoothly and tap again. AirMouse sets the pointer speed from how far you turned.' },
];

function CalibrationSection({ settings, onChange, onCalibrate }: { settings: AppSettings; onChange: (s: AppSettings) => void; onCalibrate: () => void }) {
  const c = usePalette();
  const m = settings.motion;
  const calibrated = settings.calibratedAt > 0;
  const biasOk = calibrated && Math.hypot(m.biasX, m.biasY, m.biasZ) < 0.1;
  return (
    <View style={{ gap: space.md }}>
      <T v="footnote" color={c.secondaryLabel} style={{ paddingHorizontal: space.lg }}>
        CALIBRATION
      </T>
      <Card style={{ gap: space.lg }}>
        <T v="subhead" color={c.secondaryLabel}>
          Teach AirMouse your iPhone and your screen. It takes about 20 seconds.
        </T>
        {CALIB_STEPS.map((st) => (
          <View key={st.title} style={styles.calStep}>
            <IconCircle name={st.icon} tone={st.tone} size={40} />
            <View style={{ flex: 1 }}>
              <T v="subhead" weight="600">
                {st.title}
              </T>
              <T v="footnote" color={c.secondaryLabel}>
                {st.body}
              </T>
            </View>
          </View>
        ))}
        <PrimaryButton title="Start Calibration" icon="scope" onPress={onCalibrate} />
      </Card>
      <Card style={{ gap: space.md }}>
        <T v="footnote" weight="600" color={c.secondaryLabel}>
          Last Result
        </T>
        {calibrated ? (
          <View style={styles.result}>
            <Metric value={Math.round(m.sensitivity) === Math.round(m.sensitivityY) ? `${Math.round(m.sensitivity)}` : `${Math.round(m.sensitivity)} × ${Math.round(m.sensitivityY)}`} label="Speed (pt/rad)" />
            <View style={[styles.vsep, { backgroundColor: c.separator }]} />
            <Metric value={biasOk ? 'OK' : 'High'} label="Gyro bias" color={biasOk ? c.success : c.warning} />
            <View style={[styles.vsep, { backgroundColor: c.separator }]} />
            <Metric
              value={new Date(settings.calibratedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
              label={new Date(settings.calibratedAt).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}
            />
          </View>
        ) : (
          <T v="subhead" color={c.secondaryLabel}>
            Not calibrated yet.
          </T>
        )}
        {calibrated ? (
          <Pressable
            onPress={() => onChange({ ...settings, calibratedAt: 0, motion: { ...m, biasX: 0, biasY: 0, biasZ: 0, sensitivity: DEFAULT_SETTINGS.sensitivity, sensitivityY: DEFAULT_SETTINGS.sensitivityY }, calibratedV3: [] })}
            accessibilityRole="button"
            hitSlop={8}
          >
            <T v="subhead" color={c.errorText}>
              Reset Calibration
            </T>
          </Pressable>
        ) : null}
      </Card>
    </View>
  );
}

function Metric(p: { value: string; label: string; color?: string }) {
  const c = usePalette();
  return (
    <View style={{ flex: 1, gap: 2 }}>
      <T v="title2" weight="700" color={p.color} style={roundedFont}>
        {p.value}
      </T>
      <T v="caption" color={c.secondaryLabel}>
        {p.label}
      </T>
    </View>
  );
}

function ScreenSize({ settings, onChange }: { settings: AppSettings; onChange: (s: AppSettings) => void }) {
  const c = usePalette();
  const [w, setW] = useState(String(settings.screenW));
  const [h, setH] = useState(String(settings.screenH));
  const [prev, setPrev] = useState(`${settings.screenW}x${settings.screenH}`);
  const key = `${settings.screenW}x${settings.screenH}`;
  if (prev !== key) {
    setPrev(key);
    setW(String(settings.screenW));
    setH(String(settings.screenH));
  }
  const commit = () => {
    const nw = Math.round(Number(w));
    const nh = Math.round(Number(h));
    if (nw > 0 && nh > 0) onChange({ ...settings, screenW: nw, screenH: nh });
    else {
      setW(String(settings.screenW));
      setH(String(settings.screenH));
    }
  };
  const input = [styles.sizeInput, { color: c.label, backgroundColor: c.fill }];
  return (
    <View style={styles.sizeRow}>
      <T style={{ flex: 1 }}>Size</T>
      <TextInput style={input} value={w} onChangeText={setW} onEndEditing={commit} keyboardType="number-pad" accessibilityLabel="Screen width in points" />
      <T color={c.secondaryLabel}>×</T>
      <TextInput style={input} value={h} onChangeText={setH} onEndEditing={commit} keyboardType="number-pad" accessibilityLabel="Screen height in points" />
      <T v="footnote" color={c.secondaryLabel}>
        pt
      </T>
    </View>
  );
}

const styles = StyleSheet.create({
  body: { paddingHorizontal: space.lg, gap: space.xxl },
  statusHead: { flexDirection: 'row', alignItems: 'center', gap: space.md },
  statusHalo: { width: 56, height: 56, borderRadius: 28, alignItems: 'center', justifyContent: 'center' },
  hair: { height: StyleSheet.hairlineWidth },
  transport: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  calStep: { flexDirection: 'row', gap: space.md, alignItems: 'center' },
  result: { flexDirection: 'row', alignItems: 'center', gap: space.md },
  vsep: { width: StyleSheet.hairlineWidth, alignSelf: 'stretch' },
  segmentRow: { paddingHorizontal: space.lg, paddingVertical: space.md },
  sizeRow: { flexDirection: 'row', alignItems: 'center', gap: space.sm, paddingHorizontal: space.lg, minHeight: 52 },
  sizeInput: { width: 72, textAlign: 'center', fontSize: 17, fontFamily: 'ui-rounded', paddingVertical: 7, borderRadius: 8 },
});

// Live pointer pipeline state for debugging on real devices
// (docs/spec-v3.md 4a.4). Polls a ref snapshot at ~4 Hz, only while shown.
const DIAG_MS = 250;
function DiagnosticsSection({ read, onBench }: { read: () => Diagnostics; onBench?: () => void }) {
  const [d, setD] = useState<Diagnostics>(() => read());
  useEffect(() => {
    const id = setInterval(() => setD(read()), DIAG_MS);
    return () => clearInterval(id);
  }, [read]);
  const sent = Object.entries(d.sent).sort((a, b) => b[1] - a[1]);
  const ago = d.lastMoveAgoMs === null ? 'never' : d.lastMoveAgoMs < 1000 ? 'now' : `${Math.round(d.lastMoveAgoMs / 1000)} s ago`;
  return (
    <Section header="Diagnostics" footer="Live. Moves are only sent while you hold the touch area (Hold to Point) and nothing is paused.">
      <ListRow title="Connection" value={`${d.kind ?? 'none'} · ${d.status}`} />
      <ListRow title="Paused" value={d.paused ? `Yes (${d.pausedBy.join(', ')})` : 'No'} />
      <ListRow title="Touching" value={d.touching ? 'Yes' : 'No'} />
      <ListRow title="Mode" value={d.mode} />
      <ListRow title="Gyroscope" value={`${d.gyroHz} Hz · ${d.gaps} gaps`} valueRounded />
      <ListRow title="Last Move" value={`${d.lastDx}, ${d.lastDy} · ${ago}`} valueRounded />
      <ListRow title="Not Sent (offline)" value={`${d.dropped}`} valueRounded />
      {sent.length === 0 ? <ListRow title="Sent" value="nothing yet" /> : sent.map(([k, n]) => <ListRow key={k} title={`Sent ${k}`} value={`${n}`} valueRounded />)}
      {d.link ? Object.entries(d.link).map(([k, v]) => <ListRow key={`link-${k}`} title={`Bluetooth ${k}`} value={String(v) || '—'} valueRounded />) : null}
      {d.link && onBench ? <ListRow title="Run Bluetooth Benchmark" icon="speedometer" iconColor="#5E5CE6" chevron onPress={onBench} /> : null}
    </Section>
  );
}
