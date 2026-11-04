import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, StyleSheet, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Haptics from 'expo-haptics';
import { parseAddress, parseConnectUrl, type MacAddress } from '../connect/address';
import { useNearbyMacs } from '../connect/useNearbyMacs';
import type { NearbyMac } from '../../modules/airmouse-discovery';
import type { TransportKind } from '../settings';
import type { TransportStatus } from '../transport/types';
import { scanBluetoothMacs, type BluetoothMac } from '../transport/bleMac';
import type { ConnectTarget } from '../useAirMouse';
import { Icon, IconBadge, ListRow, WarningRow, PrimaryButton, Section, SecondaryButton, T } from '../ui/components';
import { radius, space, usePalette } from '../ui/tokens';
import { Illustration } from '../ui/Illustration';

export type CurrentConnection = { kind: TransportKind; name: string; detail: string; host?: string; port?: number };

type Props = {
  visible: boolean;
  onClose: () => void;
  status: TransportStatus;
  detail?: string;
  current?: CurrentConnection;
  onConnect: (target: ConnectTarget) => void;
  onDisconnect: () => void;
  initialMode?: Mode;
  demoNearby?: NearbyMac[];
  warnings?: { text: string; onPress: () => void }[];
};

export type Mode = 'list' | 'scan' | 'manual' | 'bluetooth';

export function ConnectSheet(p: Props) {
  const c = usePalette();
  const insets = useSafeAreaInsets();
  const [mode, setMode] = useState<Mode>(p.initialMode ?? 'list');
  const nearby = useNearbyMacs(p.visible && mode === 'list');
  const macs = nearby.macs.length > 0 ? nearby.macs : (p.demoNearby ?? []);
  const [pending, setPending] = useState<string | null>(null);

  const close = () => {
    setMode('list');
    setPending(null);
    p.onClose();
  };
  const go = (target: ConnectTarget, label: string) => {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
    setPending(label);
    setMode('list');
    p.onConnect(target);
  };
  const pickWifi = (mac: MacAddress) => go({ kind: 'wifi', host: mac.host, port: mac.port, name: mac.name }, mac.name ?? mac.host);

  const connected = p.status === 'open';
  const busy = p.status === 'connecting';
  const isCurrent = (kind: TransportKind, name?: string, host?: string) =>
    !!p.current && p.current.kind === kind && ((!!name && name === p.current.name) || (!!host && host === p.current.host));
  const rowState = (kind: TransportKind, name?: string, host?: string) => {
    const cur = isCurrent(kind, name, host);
    return {
      subtitle: cur && connected ? 'Connected' : cur && busy ? 'Connecting…' : undefined,
      loading: cur && busy,
      right: cur && connected ? <Icon name="checkmark" size={17} color={c.tint} weight="semibold" /> : undefined,
    };
  };

  return (
    <Modal visible={p.visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={close}>
      <View style={[styles.root, { backgroundColor: c.grouped }]}>
        <View style={styles.nav}>
          {mode !== 'list' ? (
            <Pressable onPress={() => setMode('list')} hitSlop={12} style={styles.navBtn} accessibilityRole="button" accessibilityLabel="Back">
              <Icon name="chevron.left" size={17} color={c.tint} weight="semibold" />
              <T color={c.tint}>Back</T>
            </Pressable>
          ) : (
            <View />
          )}
          <Pressable onPress={close} hitSlop={12} accessibilityRole="button" accessibilityLabel="Done">
            <T color={c.tint} weight="600">
              Done
            </T>
          </Pressable>
        </View>

        {mode === 'scan' ? (
          <Scanner onFound={pickWifi} />
        ) : mode === 'manual' ? (
          <ManualEntry initial={p.current?.kind === 'wifi' && p.current.host ? { host: p.current.host, port: p.current.port ?? 8765 } : undefined} onConnect={pickWifi} />
        ) : mode === 'bluetooth' ? (
          <BluetoothList current={p.current} onPick={(m) => go({ kind: 'bluetooth', id: m.id, name: m.name }, m.name)} />
        ) : (
          <ScrollView contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + space.xxxl }]}>
            <View style={styles.hero}>
              <IconBadge name="laptopcomputer" color={c.tint} gradient size={64} />
              <T v="title" center>
                Connect to a Mac
              </T>
              <T v="subhead" color={c.secondaryLabel} center style={{ maxWidth: 300 }}>
                Open AirMouse on your Mac, then choose how to connect.
              </T>
            </View>

            {p.warnings?.map((w) => <WarningRow key={w.text} text={w.text} onPress={w.onPress} />)}

            <Section
              header="Nearby on Wi-Fi"
              footer={
                nearby.error
                  ? 'Can’t search the local network. Allow Local Network for AirMouse in Settings › Privacy & Security.'
                  : !nearby.supported
                    ? 'Nearby search isn’t available on this device. Scan the QR code instead.'
                    : 'Your iPhone and Mac need to be on the same Wi-Fi.'
              }
            >
              {macs.map((m) => {
                const st = rowState('wifi', m.name, m.host);
                return (
                  <ListRow
                    key={m.name}
                    title={m.name}
                    subtitle={st.subtitle ?? (m.host ? undefined : 'Resolving…')}
                    icon="laptopcomputer"
                    iconColor="#8E8E93"
                    loading={st.loading || (busy && pending === m.name && !p.current)}
                    disabled={!m.host}
                    right={st.right}
                    onPress={m.host && m.port ? () => pickWifi({ host: m.host!, port: m.port!, name: m.name }) : undefined}
                  />
                );
              })}
              {nearby.supported && macs.length === 0 ? (
                <View style={styles.searching}>
                  <ActivityIndicator />
                  <T color={c.secondaryLabel}>Looking for Macs…</T>
                </View>
              ) : null}
              {!nearby.supported && macs.length === 0 ? <ListRow title="No Macs found" /> : null}
            </Section>

            <Section header="Other Ways" footer="Bluetooth works without Wi-Fi.">
              <ListRow title="Scan QR Code" icon="qrcode.viewfinder" iconColor="#FF9F0A" chevron onPress={() => setMode('scan')} />
              <ListRow title="Enter IP Address" icon="network" iconColor="#30B0C7" chevron onPress={() => setMode('manual')} />
              <ListRow
                title="Bluetooth"
                icon="antenna.radiowaves.left.and.right"
                iconColor="#0A84FF"
                chevron
                value={p.current?.kind === 'bluetooth' && connected ? p.current.name : undefined}
                onPress={() => setMode('bluetooth')}
              />
            </Section>

            {p.status === 'error' && p.detail ? (
              <View style={[styles.banner, { backgroundColor: c.fill }]}>
                <Icon name="exclamationmark.triangle.fill" size={18} color={c.warning} />
                <T v="subhead" style={{ flex: 1 }}>
                  {p.detail}
                </T>
              </View>
            ) : null}

            {p.current ? (
              <Section>
                <ListRow
                  title={connected ? 'Disconnect' : busy ? 'Stop Connecting' : 'Forget Last Connection'}
                  subtitle={`${p.current.name} · ${p.current.detail}`}
                  destructive
                  onPress={() => {
                    setPending(null);
                    p.onDisconnect();
                  }}
                />
              </Section>
            ) : null}
          </ScrollView>
        )}
      </View>
    </Modal>
  );
}

function BluetoothList(p: { current?: CurrentConnection; onPick: (mac: BluetoothMac) => void }) {
  const c = usePalette();
  const [macs, setMacs] = useState<BluetoothMac[]>([]);
  const [error, setError] = useState<string | undefined>();
  useEffect(() => {
    let stop: (() => void) | null = null;
    try {
      stop = scanBluetoothMacs(
        (mac) => {
          setError(undefined);
          setMacs((list) => (list.some((m) => m.id === mac.id) ? list : [...list, mac].sort((a, b) => a.name.localeCompare(b.name))));
        },
        setError,
      );
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      Promise.resolve().then(() => setError(msg));
    }
    return () => stop?.();
  }, []);
  return (
    <ScrollView contentContainerStyle={styles.content}>
      <View style={styles.hero}>
        <Illustration name="connect-bluetooth" width={64} height={64} />
        <T v="title" center>
          Bluetooth
        </T>
        <T v="subhead" color={c.secondaryLabel} center style={{ maxWidth: 300 }}>
          Turn on Bluetooth in AirMouse on your Mac. No Wi-Fi needed.
        </T>
      </View>
      <Section header="Macs" footer={error}>
        {macs.map((m) => (
          <ListRow
            key={m.id}
            title={m.name}
            icon="laptopcomputer"
            iconColor="#8E8E93"
            right={p.current?.kind === 'bluetooth' && p.current.name === m.name ? <Icon name="checkmark" size={17} color={c.tint} weight="semibold" /> : undefined}
            onPress={() => p.onPick(m)}
          />
        ))}
        {macs.length === 0 ? (
          <View style={styles.searching}>
            <ActivityIndicator />
            <T color={c.secondaryLabel}>Searching…</T>
          </View>
        ) : null}
      </Section>
    </ScrollView>
  );
}

function Scanner(p: { onFound: (mac: MacAddress) => void }) {
  const c = usePalette();
  const [permission, requestPermission] = useCameraPermissions();
  const [bad, setBad] = useState(false);
  const done = useRef(false);

  if (!permission) return <View style={{ flex: 1 }} />;
  if (!permission.granted) {
    return (
      <View style={styles.centered}>
        <Illustration name="connect-qr" width={64} height={64} />
        <T v="title2" center>
          Scan the QR Code
        </T>
        <T v="subhead" color={c.secondaryLabel} center style={{ maxWidth: 290 }}>
          AirMouse uses the camera only to read the code shown on your Mac.
        </T>
        <PrimaryButton title={permission.canAskAgain ? 'Allow Camera' : 'Camera Access Is Off'} onPress={requestPermission} disabled={!permission.canAskAgain} style={{ alignSelf: 'stretch' }} />
      </View>
    );
  }
  return (
    <View style={styles.scanRoot}>
      <T v="title2" center>
        Scan the QR Code
      </T>
      <T v="subhead" color={c.secondaryLabel} center style={{ maxWidth: 300 }}>
        Point your iPhone at the code in AirMouse on your Mac.
      </T>
      <View style={styles.viewfinder}>
        <CameraView
          style={StyleSheet.absoluteFill}
          facing="back"
          barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
          onBarcodeScanned={({ data }) => {
            if (done.current) return;
            const mac = parseConnectUrl(data);
            if (!mac) {
              if (!bad) Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
              setBad(true);
              return;
            }
            done.current = true;
            Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
            p.onFound(mac);
          }}
        />
        <Corners />
      </View>
      <T v="footnote" color={bad ? c.errorText : c.secondaryLabel} center>
        {bad ? 'That’s not an AirMouse code.' : 'The code is in the AirMouse window on your Mac.'}
      </T>
    </View>
  );
}

function Corners() {
  const corner = (pos: object) => <View style={[styles.corner, pos]} />;
  return (
    <View style={StyleSheet.absoluteFill} pointerEvents="none">
      {corner({ top: 18, left: 18, borderTopWidth: 4, borderLeftWidth: 4, borderTopLeftRadius: 16 })}
      {corner({ top: 18, right: 18, borderTopWidth: 4, borderRightWidth: 4, borderTopRightRadius: 16 })}
      {corner({ bottom: 18, left: 18, borderBottomWidth: 4, borderLeftWidth: 4, borderBottomLeftRadius: 16 })}
      {corner({ bottom: 18, right: 18, borderBottomWidth: 4, borderRightWidth: 4, borderBottomRightRadius: 16 })}
    </View>
  );
}

function ManualEntry(p: { initial?: MacAddress; onConnect: (mac: MacAddress) => void }) {
  const c = usePalette();
  const [host, setHost] = useState(p.initial?.host ?? '');
  const [port, setPort] = useState(String(p.initial?.port ?? 8765));
  const parsed = parseAddress(host, port);
  const input = [styles.input, { color: c.label }];
  return (
    <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <View style={styles.hero}>
          <Illustration name="connect-ip" width={64} height={64} />
          <T v="title" center>
            Enter IP Address
          </T>
          <T v="subhead" color={c.secondaryLabel} center style={{ maxWidth: 300 }}>
            The address is shown under the QR code in AirMouse on your Mac.
          </T>
        </View>
        <Section footer={host && !parsed ? 'Check the address and port.' : 'Example: 192.168.1.20, port 8765'}>
          <View style={styles.field}>
            <T style={styles.fieldLabel}>IP Address</T>
            <TextInput
              style={input}
              value={host}
              onChangeText={setHost}
              placeholder="192.168.1.20"
              placeholderTextColor={c.tertiaryLabel}
              keyboardType="numbers-and-punctuation"
              autoCapitalize="none"
              autoCorrect={false}
              autoFocus
              returnKeyType="next"
              accessibilityLabel="Address"
            />
          </View>
          <View style={styles.field}>
            <T style={styles.fieldLabel}>Port</T>
            <TextInput
              style={input}
              value={port}
              onChangeText={setPort}
              keyboardType="number-pad"
              placeholder="8765"
              placeholderTextColor={c.tertiaryLabel}
              accessibilityLabel="Port"
            />
          </View>
        </Section>
        <PrimaryButton title="Connect" icon="link" disabled={!parsed} onPress={() => parsed && p.onConnect(parsed)} />
        <SecondaryButton title="Use Default Port" plain onPress={() => setPort('8765')} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  nav: { height: 56, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: space.margin },
  navBtn: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  content: { paddingHorizontal: space.margin, gap: space.xxl, paddingBottom: space.xxxl },
  hero: { alignItems: 'center', gap: space.sm, paddingTop: space.sm },
  searching: { flexDirection: 'row', alignItems: 'center', gap: space.md, paddingHorizontal: space.lg, minHeight: 52 },
  banner: { flexDirection: 'row', gap: space.md, alignItems: 'center', padding: space.lg, borderRadius: radius.button, borderCurve: 'continuous' },
  centered: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: space.lg, padding: space.xxxl },
  scanRoot: { flex: 1, alignItems: 'center', gap: space.md, paddingHorizontal: space.margin, paddingTop: space.sm },
  viewfinder: { width: '100%', aspectRatio: 1, borderRadius: 32, borderCurve: 'continuous', overflow: 'hidden', backgroundColor: '#000', marginVertical: space.md },
  corner: { position: 'absolute', width: 44, height: 44, borderColor: '#FFFFFF' },
  field: { flexDirection: 'row', alignItems: 'center', minHeight: 52, paddingHorizontal: space.lg, gap: space.md },
  fieldLabel: { width: 96 },
  input: { flex: 1, fontSize: 17, paddingVertical: 12 },
});
