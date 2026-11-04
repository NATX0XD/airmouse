import { useEffect, useRef, useState } from 'react';
import { LayoutAnimation, Modal, Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Haptics from 'expo-haptics';
import { actionsFor, startAt, STEPS, stepCompleted, type PermissionId, type PermissionStatus, type Statuses } from '../setup/steps';
import { Icon, IconCircle, Material, PrimaryButton, SecondaryButton, StepRing, T, Tag, type CircleTone, type SymbolName } from '../ui/components';
import { LinearGradient } from 'expo-linear-gradient';
import { Illustration } from '../ui/Illustration';
import { radius, space, usePalette } from '../ui/tokens';

// Same pattern as the Mac "Permissions" page: progress ring, checklist rows
// (icon circle, title, Required/Optional tag, live status), current row
// expanded with the why + action.

type Copy = { icon: SymbolName; tone: CircleTone; title: string; why: string; allow: string; granted: string; waiting: string };

const COPY: Record<PermissionId, Copy> = {
  localNetwork: {
    icon: 'wifi',
    tone: 'teal',
    title: 'Local Network',
    why: 'AirMouse needs Local Network access to find your Mac on Wi-Fi and send it the pointer.',
    allow: 'Allow Local Network',
    granted: 'Your iPhone can find your Mac',
    waiting: 'Not allowed yet',
  },
  bluetooth: {
    icon: 'antenna.radiowaves.left.and.right',
    tone: 'indigo',
    title: 'Bluetooth',
    why: 'With Bluetooth, your iPhone talks to your Mac directly, without Wi-Fi.',
    allow: 'Allow Bluetooth',
    granted: 'Bluetooth is ready',
    waiting: 'Not allowed yet',
  },
  camera: {
    icon: 'qrcode.viewfinder',
    tone: 'orange',
    title: 'Camera',
    why: 'Scan the QR code in AirMouse on your Mac to connect in one step.',
    allow: 'Allow Camera',
    granted: 'Ready to scan QR codes',
    waiting: 'Not allowed yet',
  },
  motion: {
    icon: 'gyroscope',
    tone: 'green',
    title: 'Motion Sensors',
    why: 'The gyroscope feels every turn of your hand and turns it into pointer motion. No permission needed.',
    allow: 'Checking…',
    granted: 'Gyroscope is ready',
    waiting: 'Checking…',
  },
};

function statusLine(id: PermissionId, s: PermissionStatus): string {
  if (s === 'granted') return COPY[id].granted;
  if (s === 'denied') return 'Turned off in Settings';
  if (s === 'unavailable') return 'Not available on this device';
  return COPY[id].waiting;
}

type Props = {
  visible: boolean;
  statuses: Statuses;
  request: (id: PermissionId, status: PermissionStatus) => void;
  startStep?: PermissionId;
  onDone: () => void;
};

export function SetupFlow(p: Props) {
  const c = usePalette();
  const insets = useSafeAreaInsets();
  const [open, setOpen] = useState<number>(p.startStep ? startAt(p.startStep).index : 0);
  const done = STEPS.filter((s) => stepCompleted(s, p.statuses[s.id])).length;
  const all = done === STEPS.length;
  const required = STEPS.filter((s) => s.required);
  const requiredOk = required.every((s) => p.statuses[s.id] !== 'unknown');

  // When the open step gets granted: haptic, then move to the next open item.
  const prev = useRef(p.statuses);
  useEffect(() => {
    const before = prev.current;
    prev.current = p.statuses;
    const id = STEPS[open].id;
    if (before[id] !== 'granted' && p.statuses[id] === 'granted') {
      if (id !== 'motion') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      const nextOpen = STEPS.findIndex((s, i) => i > open && !stepCompleted(s, p.statuses[s.id]));
      if (nextOpen >= 0) {
        const t = setTimeout(() => {
          LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
          setOpen(nextOpen);
        }, 700);
        return () => clearTimeout(t);
      }
    }
  }, [p.statuses, open]);

  const select = (i: number) => {
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setOpen(i);
  };

  return (
    <Modal visible={p.visible} animationType="slide" presentationStyle="fullScreen" onRequestClose={p.onDone}>
      <LinearGradient colors={['#090B2A', '#24135A', '#100D36']} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={[styles.root, { paddingTop: insets.top + space.sm }]}> 
        <ScrollView contentContainerStyle={styles.content}>
          <Illustration name={open === 0 ? 'calib-place' : 'calib-done'} width={190} height={130} />
          <T v="largeTitle" color="#FFFFFF">Permissions</T>
          <T v="subhead" color="rgba(255,255,255,0.72)">
            AirMouse needs a few permissions to find your Mac and read the motion sensors.
          </T>

          <View style={styles.summary}>
            <StepRing done={done} total={STEPS.length} />
            <View style={{ flex: 1 }}>
              <T v="title2" color="#FFFFFF">{all ? 'AirMouse Is Ready' : 'Almost Ready'}</T>
              <T v="subhead" color="rgba(255,255,255,0.72)">
                {all ? 'Everything is set up.' : `${STEPS.length - done} more to check.`}
              </T>
            </View>
          </View>

          <View style={styles.permissionStack}>
            {STEPS.map((step, i) => {
              const status = p.statuses[step.id];
              const copy = COPY[step.id];
              const ok = stepCompleted(step, status);
              const isOpen = i === open;
              const a = actionsFor(step, status);
              return (
                <Material key={step.id} style={styles.permissionCard}>
                  <Pressable onPress={() => select(i)} accessibilityRole="button" accessibilityState={{ expanded: isOpen }} accessibilityLabel={`${copy.title}, ${statusLine(step.id, status)}`}>
                    <View style={styles.row}>
                      <IconCircle name={copy.icon} tone={copy.tone} size={40} />
                      <View style={{ flex: 1, gap: 2 }}>
                        <View style={styles.titleLine}>
                          <T v="headline">{copy.title}</T>
                          <Tag text={step.automatic ? 'Automatic' : step.required ? 'Required' : 'Optional'} />
                        </View>
                        {!isOpen ? (
                          <T v="footnote" color={status === 'denied' ? c.errorText : c.secondaryLabel}>
                            {statusLine(step.id, status)}
                          </T>
                        ) : null}
                      </View>
                      {status === 'unavailable' ? (
                        <Icon name="minus.circle.fill" size={24} color={c.tertiaryLabel} />
                      ) : ok ? (
                        <Icon name="checkmark.circle.fill" size={24} color={c.success} />
                      ) : status === 'denied' ? (
                        <Icon name="exclamationmark.circle.fill" size={24} color={c.warning} />
                      ) : (
                        <Icon name="circle.dotted" size={24} color={c.tertiaryLabel} />
                      )}
                      <Icon name={isOpen ? 'chevron.up' : 'chevron.down'} size={13} color={c.tertiaryLabel} weight="semibold" />
                    </View>
                  </Pressable>
                  {isOpen ? (
                    <View style={styles.detail}>
                      <T v="subhead" color={c.secondaryLabel}>
                        {copy.why}
                      </T>
                      <View style={[styles.chip, { backgroundColor: ok ? 'rgba(48,209,88,0.15)' : status === 'denied' ? 'rgba(255,69,58,0.12)' : c.fill }]}>
                        <Icon name={ok ? 'checkmark.circle.fill' : status === 'denied' ? 'xmark.circle.fill' : 'circle.dotted'} size={15} color={ok ? c.success : status === 'denied' ? c.error : c.secondaryLabel} />
                        <T v="subhead" weight="600" color={status === 'denied' ? c.errorText : c.label}>
                          {statusLine(step.id, status)}
                        </T>
                      </View>
                      {a.primary === 'request' || a.primary === 'openSettings' ? (
                        <PrimaryButton compact title={a.primary === 'openSettings' ? 'Open Settings' : copy.allow} onPress={() => p.request(step.id, status)} style={{ alignSelf: 'flex-start' }} />
                      ) : null}
                    </View>
                  ) : null}
                </Material>
              );
            })}
          </View>
          <T v="footnote" color="rgba(255,255,255,0.64)" style={{ paddingHorizontal: space.lg }}>
            Status updates by itself while this page is open. You can change these later in Settings.
          </T>
        </ScrollView>

        <View style={[styles.footer, { paddingBottom: insets.bottom + space.md }]}> 
          <PrimaryButton title={all ? 'Get Started' : 'Continue'} onPress={p.onDone} disabled={!requiredOk} />
          <SecondaryButton title="Skip for Now" plain onPress={p.onDone} style={all && { opacity: 0 }} disabled={all} />
        </View>
      </LinearGradient>
    </Modal>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { paddingHorizontal: space.margin, paddingTop: space.lg, paddingBottom: space.xl, gap: space.md },
  summary: { flexDirection: 'row', alignItems: 'center', gap: space.lg, paddingVertical: space.sm },
  permissionStack: { gap: space.md },
  permissionCard: { borderRadius: radius.card, borderCurve: 'continuous', overflow: 'hidden', borderWidth: 1, borderColor: 'rgba(255,255,255,0.14)' },
  sep: { height: StyleSheet.hairlineWidth, marginLeft: 68 },
  row: { flexDirection: 'row', alignItems: 'center', gap: space.md, paddingHorizontal: space.lg, paddingVertical: 14 },
  titleLine: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  detail: { paddingLeft: 68, paddingRight: space.lg, paddingBottom: space.lg, gap: space.md },
  chip: { flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: 12, paddingVertical: 8, borderRadius: 12, alignSelf: 'flex-start' },
  footer: { paddingHorizontal: space.margin, paddingTop: space.sm, gap: 2 },
});
