import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AppState, Linking, StyleSheet, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { useKeepAwake } from 'expo-keep-awake';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useAirMouse, type ConnectTarget } from './src/useAirMouse';
import { DEFAULT_APP_SETTINGS, loadSettings, saveSettings, type AppSettings } from './src/settings';
import { parseConnectUrl } from './src/connect/address';
import type { CalibTarget, InboundMsg, TransportStatus } from './src/transport/types';
import type { MotionSettings } from './src/motion/engine';
import { markCalibrated, shouldPromptCalibration } from './src/setup/calibrated';
import type { BluetoothMac } from './src/transport/bleMac';
import { RemoteScreen } from './src/screens/RemoteScreen';
import { SensorsScreen } from './src/screens/SensorsScreen';
import { SettingsScreen } from './src/screens/SettingsScreen';
import { ConnectSheet, type CurrentConnection, type Mode as ConnectMode } from './src/screens/ConnectSheet';
import { CalibrationFlow, type CalibResult, type CalibStep } from './src/screens/calibration/CalibrationFlow';
import { ErrorBoundary } from './src/ui/ErrorBoundary';
import { SetupFlow } from './src/screens/SetupFlow';
import { usePermissions } from './src/setup/usePermissions';
import { missing, STEPS, stepCompleted, type PermissionId } from './src/setup/steps';
import { FLAG_KEYS, launchStep, shouldStartTour, TOUR_IDLE, tourNext, tourSkip, tourStart, type Tour } from './src/setup/onboarding';
import { WelcomeFlow } from './src/screens/WelcomeFlow';
import { ExplainerFlow } from './src/screens/ExplainerFlow';
import { TourOverlay, TourProvider } from './src/ui/Tour';
import { WARNING_TEXT } from './src/setup/warnings';
import { TabBar } from './src/ui/TabBar';
import { usePalette } from './src/ui/tokens';
import { Toast } from './src/ui/Toast';
import { CalibrationPrompt } from './src/ui/CalibrationPrompt';
import { calibrationPaused, calibrationShouldClose } from './src/motion/pause';

type Tab = 'remote' | 'sensors' | 'settings';

const SETUP_KEY = FLAG_KEYS.setup;

// Screenshot hooks, only in dev or in builds bundled with
// EXPO_PUBLIC_AIRMOUSE_PREVIEW=1 (never in the normal device build), e.g. `xcrun simctl openurl booted
// "airmouse://preview?screen=calib&step=left&connected=1"`.
type Preview = {
  screen?: Tab | 'connect' | 'calib' | 'setup' | 'welcome' | 'tour';
  page?: number;
  perm?: PermissionId;
  step?: CalibStep;
  progress?: number;
  pressed?: boolean;
  scroll?: number;
  connected?: boolean;
  connectMode?: ConnectMode;
};

const PREVIEW_ENABLED = __DEV__ || process.env.EXPO_PUBLIC_AIRMOUSE_PREVIEW === '1';
// Simulator screenshots can also set the query in AsyncStorage (no URL prompt).
const PREVIEW_KEY = 'airmouse.preview';

function parsePreview(url: string | null | undefined): Preview | null {
  if (!PREVIEW_ENABLED || !url) return null;
  const m = /^airmouse:\/\/preview\??(.*)$/i.exec(url);
  if (!m) return null;
  const q = Object.fromEntries(m[1].split('&').filter(Boolean).map((kv) => kv.split('=').map(decodeURIComponent)));
  return {
    screen: q.screen as Preview['screen'],
    step: q.step as CalibStep | undefined,
    progress: q.progress ? Number(q.progress) : undefined,
    pressed: q.pressed === '1',
    scroll: q.scroll ? Number(q.scroll) : undefined,
    page: q.page ? Number(q.page) : undefined,
    connected: q.connected === '1',
    connectMode: q.mode as ConnectMode | undefined,
    perm: q.perm as PermissionId | undefined,
  };
}

const DEMO_MAC = "Nattakit's MacBook Pro";
const KEYBOARD_KEEP_MS = 2000; // focus lost on the Mac: keep the keyboard if the user typed this recently

function practiceSummary(m: { hits?: number; total?: number; ms?: number }): string {
  const parts: string[] = [];
  // Mac: hits = targets hit, total = all clicks (hits + misses).
  if (m.hits !== undefined && m.total) parts.push(`${m.hits} targets · ${Math.round((100 * m.hits) / m.total)}% accuracy`);
  else if (m.hits !== undefined) parts.push(`${m.hits} targets`);
  if (m.ms !== undefined) parts.push(`${Math.round(m.ms)} ms avg`);
  return parts.length ? `Practice: ${parts.join(' · ')}` : 'Practice finished';
}

function savedTarget(s: AppSettings): ConnectTarget | null {
  if (s.transport === 'bluetooth' && s.bleId) return { kind: 'bluetooth', id: s.bleId, name: s.bleName || 'Mac' };
  if (s.transport === 'wifi' && s.host) return { kind: 'wifi', host: s.host, port: s.port, name: s.macName || undefined };
  return null;
}

function AirMouseApp() {
  useKeepAwake(); // a remote that sleeps mid-presentation is useless
  const c = usePalette();
  const [tab, setTab] = useState<Tab>('remote');
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_APP_SETTINGS);
  const [loaded, setLoaded] = useState(false);
  const [connectOpen, setConnectOpen] = useState(false);
  const [calibOpen, setCalibOpenState] = useState(false);
  const [calibSession, setCalibSession] = useState(0);
  const setCalibOpen = useCallback((v: boolean) => {
    if (v) setCalibSession((n) => n + 1);
    setCalibOpenState(v);
  }, []);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [setupOpen, setSetupOpen] = useState(false);
  const [setupStep, setSetupStep] = useState<PermissionId | undefined>();
  const [setupSession, setSetupSession] = useState(0);
  const perms = usePermissions(setupOpen);
  const [welcomeOpen, setWelcomeOpen] = useState(false);
  const [welcomeSession, setWelcomeSession] = useState(0);
  const [explainerOpen, setExplainerOpen] = useState(false);
  const [tour, setTour] = useState<Tour>(TOUR_IDLE);
  const [tourDone, setTourDone] = useState(true); // set from storage at launch
  const openSetup = useCallback((step?: PermissionId) => {
    setConnectOpen(false);
    setSetupStep(step);
    setSetupSession((n) => n + 1);
    // iOS presents one modal at a time: let the Connect sheet go first.
    setTimeout(() => setSetupOpen(true), 350);
  }, []);
  const settingsRef = useRef(settings);
  const pendingTarget = useRef<ConnectTarget | null>(null);

  const update = useCallback((s: AppSettings) => {
    settingsRef.current = s;
    setSettings(s);
    saveSettings(s);
  }, []);

  // Mac keyboard focus and Click Practice (docs/spec-v3.md 3, 6).
  const [keyboardOpen, setKeyboardOpen] = useState(false);
  const [keyboardField, setKeyboardField] = useState(0);
  const lastTypedAt = useRef(0);
  const onTyped = useCallback(() => {
    lastTypedAt.current = Date.now();
  }, []);
  const [practiceRunning, setPracticeRunning] = useState(false);
  const [toast, setToast] = useState<{ id: number; text: string; practice?: boolean }>({ id: 0, text: '' });
  const showToast = useCallback((text: string, practice?: boolean) => setToast((t) => ({ id: t.id + 1, text, practice })), []);
  const blockingModal = useRef(false);

  const [calibHit, setCalibHit] = useState<{ target: CalibTarget; n: number } | null>(null);

  const onMessage = useCallback((m: InboundMsg) => {
    if (m.t === 'calib' && m.step === 'hit') {
      const target = m.target;
      setCalibHit((h) => ({ target, n: (h?.n ?? 0) + 1 }));
      return;
    }
    if (m.t === 'calib') {
      setConnectOpen(false);
      setCalibOpen(m.step === 'request');
      return;
    }
    if (m.t === 'focus') {
      if (m.editable) {
        if (blockingModal.current) return; // calibration / setup on screen: don't steal it
        setTab('remote');
        setKeyboardField((n) => n + 1);
        setKeyboardOpen(true);
      } else if (Date.now() - lastTypedAt.current > KEYBOARD_KEEP_MS) {
        setKeyboardOpen(false);
      }
      return;
    }
    if (m.t === 'practice') {
      if (m.step === 'running') {
        setPracticeRunning(true);
        return;
      }
      setPracticeRunning(false);
      if (m.step === 'result') showToast(practiceSummary(m), true);
      return;
    }
    const s = settingsRef.current;
    const next = {
      ...s,
      screenW: m.w,
      screenH: m.h,
      screenWMm: m.wMm ?? s.screenWMm,
      screenHMm: m.hMm ?? s.screenHMm,
      screenName: m.name ?? s.screenName,
    };
    if (next.screenW !== s.screenW || next.screenH !== s.screenH || next.screenWMm !== s.screenWMm || next.screenHMm !== s.screenHMm || next.screenName !== s.screenName) update(next);
  }, [update, setCalibOpen, showToast]);

  const onBluetoothId = useCallback((mac: BluetoothMac) => {
    const s = settingsRef.current;
    if (s.transport === 'bluetooth' && s.bleName === mac.name) update({ ...s, bleId: mac.id });
  }, [update]);

  const air = useAirMouse(settings, { onMessage, onBluetoothId });
  const { connect, setPaused, setTouching, setAiming, setMotionOverride, bench } = air;
  const benchRef = useRef(bench);
  useEffect(() => {
    benchRef.current = bench;
  }, [bench]);
  const liveScreen = useRef(air.screen);
  useEffect(() => {
    liveScreen.current = air.screen;
  }, [air.screen]);

  // Calibration verify: cursor live with the new (unsaved) settings, no hold.
  const onVerify = useCallback((m: MotionSettings | null) => {
    setMotionOverride(m);
    setAiming(m !== null);
  }, [setAiming, setMotionOverride]);

  // Stable: `connect` changes whenever the Mac reports a new screen size, and
  // the launch / deep-link effects below must not re-run (reconnect, reopen
  // onboarding) because of that.
  const connectRef = useRef(connect);
  useEffect(() => {
    connectRef.current = connect;
  }, [connect]);
  const connectTo = useCallback((t: ConnectTarget) => {
    pendingTarget.current = t;
    connectRef.current(t);
  }, []);

  // Load settings, then auto-connect to the last Mac (or open Connect).
  useEffect(() => {
    let alive = true;
    const previewQuery = PREVIEW_ENABLED ? AsyncStorage.getItem(PREVIEW_KEY).catch(() => null) : Promise.resolve(null);
    const flag = (k: string) => AsyncStorage.getItem(k).then((v) => v === '1').catch(() => false);
    Promise.all([loadSettings(), flag(SETUP_KEY), previewQuery, flag(FLAG_KEYS.welcome), flag(FLAG_KEYS.tour)]).then(([s, setupDone, pq, welcomeDone, tourSeen]) => {
      if (!alive) return;
      const pv = pq ? parsePreview(`airmouse://preview?${pq}`) : null;
      if (pv) {
        settingsRef.current = s;
        setSettings(s);
        setLoaded(true);
        setPreview(pv);
        setConnectOpen(pv.screen === 'connect');
        setCalibOpen(pv.screen === 'calib');
        setSetupStep(pv.perm);
        setSetupOpen(pv.screen === 'setup');
        setWelcomeOpen(pv.screen === 'welcome');
        if (pv.screen === 'tour') {
          setTab('remote');
          setTour({ index: pv.step ? Number(pv.step) : 0, active: true });
        }
        if (pv.screen === 'remote' || pv.screen === 'sensors' || pv.screen === 'settings') setTab(pv.screen);
        return;
      }
      setTourDone(tourSeen);
      const fixed = s.transport === 'ble' || s.transport === 'hid' ? { ...s, transport: 'wifi' as const } : s;
      settingsRef.current = fixed;
      setSettings(fixed);
      setLoaded(true);
      const target = savedTarget(fixed);
      if (target && fixed.autoConnect) connectTo(target);
      const first = launchStep({ welcome: welcomeDone, setup: setupDone, tour: tourSeen }, !!target);
      if (first === 'welcome') setWelcomeOpen(true);
      else if (first === 'setup') setSetupOpen(true);
      else if (first === 'connect') setConnectOpen(true);
    });
    return () => {
      alive = false;
    };
  }, [connectTo]);

  // Remember a target once it actually connects; close the Connect sheet.
  useEffect(() => {
    if (air.status !== 'open' || !pendingTarget.current) return;
    const t = pendingTarget.current;
    pendingTarget.current = null;
    const s = settingsRef.current;
    if (t.kind === 'wifi') update({ ...s, transport: 'wifi', host: t.host, port: t.port, macName: t.name ?? (s.host === t.host ? s.macName : ''), hasConnected: true });
    else if (t.kind === 'bluetooth') update({ ...s, transport: 'bluetooth', bleId: t.id, bleName: t.name, hasConnected: true });
    const id = setTimeout(() => setConnectOpen(false), 450);
    return () => clearTimeout(id);
  }, [air.status, update]);

  // QR links opened from the Camera app, and dev previews.
  useEffect(() => {
    const handle = (url: string | null | undefined) => {
      if (!url) return;
      // Bluetooth benchmark: airmouse://ble-bench?inflight=1 (Diagnostics shows the result).
      const b = /^airmouse:\/\/ble-bench(?:\?.*inflight=(\d+))?/i.exec(url);
      if (b) {
        benchRef.current(b[1] ? { inFlight: Number(b[1]) } : undefined);
        return;
      }
      const p = parsePreview(url);
      if (p) {
        setPreview(p);
        setConnectOpen(p.screen === 'connect');
        setSetupOpen(p.screen === 'setup');
        if (p.screen === 'setup') {
          setSetupStep(p.perm);
          setSetupSession((n) => n + 1);
        }
        setCalibOpen(p.screen === 'calib');
        if (p.screen === 'remote' || p.screen === 'sensors' || p.screen === 'settings') setTab(p.screen);
        return;
      }
      const mac = parseConnectUrl(url);
      if (mac) connectTo({ kind: 'wifi', host: mac.host, port: mac.port, name: mac.name });
    };
    Linking.getInitialURL().then(handle).catch(() => {});
    const sub = Linking.addEventListener('url', (e) => handle(e.url));
    return () => sub.remove();
  }, [connectTo]);

  const fake = preview?.connected;
  const status: TransportStatus = fake ? 'open' : air.status;
  const kind = fake ? 'wifi' : air.kind;

  const current: CurrentConnection | undefined = useMemo(() => {
    if (fake) return { kind: 'wifi', name: DEMO_MAC, detail: '192.168.1.20:8765', host: '192.168.1.20', port: 8765 };
    const t = savedTarget(settings);
    if (!t) return undefined;
    if (t.kind === 'wifi') return { kind: 'wifi', name: t.name || t.host, detail: `${t.host}:${t.port}`, host: t.host, port: t.port };
    if (t.kind === 'bluetooth') return { kind: 'bluetooth', name: t.name, detail: 'Bluetooth' };
    return undefined;
  }, [settings, fake]);

  const macName = current?.name ?? '';
  const connectionLabel = status === 'open' ? macName : status === 'connecting' ? `Connecting to ${macName}…` : current ? macName : 'Connect to a Mac';
  const connectionDetail = status === 'open' ? `Connected · ${current?.detail ?? ''}` : current ? (status === 'error' ? 'Not reachable' : current.detail) : 'Not connected';

  const modalOpen = connectOpen || calibOpen || setupOpen || welcomeOpen;
  useEffect(() => {
    blockingModal.current = calibOpen || setupOpen || welcomeOpen;
  }, [calibOpen, setupOpen, welcomeOpen]);
  // Keyboard and practice only make sense while connected.
  useEffect(() => {
    if (status === 'open') return;
    setKeyboardOpen(false);
    setPracticeRunning(false);
  }, [status]);
  useEffect(() => {
    if (!shouldStartTour({ tourDone, connected: status === 'open', onRemote: tab === 'remote', modalOpen, active: tour.active })) return;
    const id = setTimeout(() => setTour(tourStart()), 900);
    return () => clearTimeout(id);
  }, [tourDone, status, tab, modalOpen, tour.active]);

  // Pointing pause = "calibration is on screen and the app is in front".
  // Derived from state, so every exit path (Done, auto-close, Cancel, Mac
  // cancel, disconnect, background) resumes motion. See motion/pause.ts.
  const [appState, setAppState] = useState<string>(AppState.currentState ?? 'active');
  useEffect(() => {
    const sub = AppState.addEventListener('change', (st) => {
      setAppState(st);
      if (st === 'background') setTouching(false); // a touch can't survive backgrounding
    });
    return () => sub.remove();
  }, [setTouching]);
  useEffect(() => {
    setPaused('calibration', calibrationPaused({ calibOpen, preview: !!preview, appActive: appState !== 'background' }));
  }, [calibOpen, preview, appState, setPaused]);
  const calibStartedConnected = useRef(false);
  const statusRef = useRef(air.status);
  useEffect(() => {
    statusRef.current = air.status;
  }, [air.status]);
  useEffect(() => {
    if (calibOpen) calibStartedConnected.current = statusRef.current === 'open'; // once, when it opens
  }, [calibOpen, calibSession]);
  useEffect(() => {
    if (preview) return;
    if (calibrationShouldClose({ calibOpen, appState, startedConnected: calibStartedConnected.current, connected: air.status === 'open' })) setCalibOpen(false);
  }, [calibOpen, appState, air.status, preview, setCalibOpen]);

  const hideToast = useCallback(() => setToast((t) => ({ ...t, id: 0 })), []);
  const closeCalibration = useCallback((finishedRun: boolean) => {
    setCalibOpen(false);
    if (finishedRun) {
      setTab('remote');
      setTimeout(() => showToast('Calibrated'), 350); // after the sheet slides away
    }
  }, [setCalibOpen, showToast]);

  const missingPerms = missing(perms.statuses);
  const permissionsDone = STEPS.filter((st) => stepCompleted(st, perms.statuses[st.id])).length;
  const warnings = missingPerms.map((id) => ({ text: WARNING_TEXT[id], onPress: () => openSetup(id) }));
  const finishSetup = useCallback(() => {
    AsyncStorage.setItem(SETUP_KEY, '1').catch(() => {});
    setSetupOpen(false);
    if (!savedTarget(settingsRef.current)) setTimeout(() => setConnectOpen(true), 450);
  }, []);

  const finishWelcome = useCallback(() => {
    AsyncStorage.setItem(FLAG_KEYS.welcome, '1').catch(() => {});
    setWelcomeOpen(false);
    AsyncStorage.getItem(SETUP_KEY)
      .then((v) => {
        if (v === '1') {
          if (!savedTarget(settingsRef.current)) setTimeout(() => setConnectOpen(true), 450);
        } else setTimeout(() => setSetupOpen(true), 450);
      })
      .catch(() => {});
  }, []);
  const endTour = useCallback(() => {
    setTour(TOUR_IDLE);
    setTourDone(true);
    AsyncStorage.setItem(FLAG_KEYS.tour, '1').catch(() => {});
  }, []);

  const finishCalibration = useCallback((r: CalibResult) => {
    const s = settingsRef.current;
    const screen = liveScreen.current ?? { w: s.screenW, h: s.screenH, name: s.screenName };
    update({ ...s, calibratedAt: Date.now(), motion: { ...s.motion, ...r }, calibratedV3: markCalibrated(s.calibratedV3 ?? [], screen) });
  }, [update]);

  // "Calibrate for Accurate Pointing" on Remote, once per uncalibrated Mac display.
  // Also comes back after a cancelled calibration; "Later" hides it for the session.
  const [promptLater, setPromptLater] = useState(false);
  const [promptStarting, setPromptStarting] = useState(false);
  const wantPrompt = shouldPromptCalibration({
    connected: air.status === 'open' && !preview,
    screen: air.screen,
    calibrated: settings.calibratedV3 ?? [],
    dismissed: promptLater,
    busy: modalOpen || tour.active || promptStarting,
  });
  // iOS presents one modal at a time: wait for the Connect sheet to go away.
  const [promptVisible, setPromptVisible] = useState(false);
  useEffect(() => {
    if (!wantPrompt) {
      setPromptVisible(false);
      return;
    }
    const id = setTimeout(() => setPromptVisible(true), 650);
    return () => clearTimeout(id);
  }, [wantPrompt]);
  const startFromPrompt = useCallback(() => {
    setPromptStarting(true);
    setTimeout(() => {
      setCalibOpen(true);
      setPromptStarting(false);
    }, 350); // after the popup fades out
  }, [setCalibOpen]);

  return (
    <View style={[styles.root, { backgroundColor: tab === 'remote' ? c.grouped : c.grouped }]}>
      <StatusBar style="auto" />
      {loaded || preview ? (
        <>
          {tab === 'remote' && (
            <RemoteScreen
              settings={settings}
              status={status}
              kind={kind}
              macName={macName}
              gyroAvailable={preview ? true : air.gyroAvailable}
              send={air.send}
              setTouching={air.setTouching}
              onOpenConnect={() => setConnectOpen(true)}
              onCalibrate={() => setCalibOpen(true)}
              forcePressed={preview?.pressed}
              warning={warnings[0]}
              onModeChange={(mode) => update({ ...settingsRef.current, mode })}
              keyboardOpen={keyboardOpen}
              keyboardField={keyboardField}
              onKeyboard={(open) => {
                if (open) setKeyboardField((n) => n + 1);
                setKeyboardOpen(open);
              }}
              onTyped={onTyped}
              practiceRunning={practiceRunning}
              onPractice={(start) => {
                air.send({ t: 'practice', step: start ? 'start' : 'stop' });
                if (!start) setPracticeRunning(false);
              }}
            />
          )}
          {tab === 'sensors' && <SensorsScreen gyroHistory={air.history} demo={!!preview} initialScroll={preview?.scroll} />}
          {tab === 'settings' && (
            <SettingsScreen
              settings={settings}
              onChange={update}
              connectionLabel={connectionLabel}
              connectionDetail={connectionDetail}
              screenFromMac={!!air.screen || !!fake}
              onOpenConnect={() => setConnectOpen(true)}
              onCalibrate={() => setCalibOpen(true)}
              onOpenSetup={() => openSetup()}
              missingCount={missingPerms.length}
              permissionsDone={permissionsDone}
              initialScroll={preview?.scroll}
              status={status}
              kind={kind}
              macName={macName}
              diagnostics={air.diagnostics}
              onBench={() => air.bench()}
              onShowTour={() => {
                setTab('remote');
                setTimeout(() => setTour(tourStart()), 400);
              }}
              onShowWelcome={() => {
                setWelcomeSession((n) => n + 1);
                setWelcomeOpen(true);
              }}
              onShowExplainer={() => setExplainerOpen(true)}
            />
          )}
          <TabBar
            tabs={[
              { key: 'remote', label: 'Remote', icon: 'cursorarrow.rays' },
              { key: 'sensors', label: 'Sensors', icon: 'waveform.path.ecg' },
              { key: 'settings', label: 'Settings', icon: 'gearshape' },
            ]}
            value={tab}
            onChange={setTab}
          />
          <Toast
            id={toast.id}
            text={toast.text}
            icon={toast.practice ? 'target' : undefined}
            iconColor={toast.practice ? c.tint : undefined}
            durationMs={toast.practice ? 4500 : undefined}
            onHidden={hideToast}
          />
          <TourOverlay tour={tour} onNext={() => {
              const n = tourNext(tour);
              if (n.active) setTour(n);
              else endTour();
            }} onSkip={endTour} />
        </>
      ) : null}

      <ConnectSheet
        key={preview?.connectMode ?? 'connect'}
        visible={connectOpen}
        onClose={() => setConnectOpen(false)}
        status={status}
        detail={air.detail}
        current={current}
        onConnect={connectTo}
        onDisconnect={() => {
          pendingTarget.current = null;
          if (status === 'open' || status === 'connecting') air.disconnect();
          else update({ ...settingsRef.current, host: '', macName: '', bleId: '', bleName: '' });
        }}
        initialMode={preview?.connectMode}
        warnings={warnings}
        demoNearby={preview?.screen === 'connect' ? [{ name: DEMO_MAC, host: '192.168.1.20', port: 8765 }, { name: 'Studio Mac mini' }] : undefined}
      />

      <CalibrationPrompt visible={promptVisible && wantPrompt} onStart={startFromPrompt} onLater={() => setPromptLater(true)} />

      <WelcomeFlow key={`welcome-${welcomeSession}-${preview?.page ?? 0}`} visible={welcomeOpen} startPage={preview?.page} onDone={finishWelcome} addGyroListener={air.addGyroListener} />
      <ExplainerFlow visible={explainerOpen} onDone={() => setExplainerOpen(false)} addGyroListener={air.addGyroListener} />

      <SetupFlow
        key={`setup-${setupSession}-${setupStep ?? ''}`}
        visible={setupOpen}
        statuses={perms.statuses}
        request={perms.request}
        startStep={setupStep}
        onDone={finishSetup}
      />

      <CalibrationFlow
        key={`${preview?.step ?? 'calib'}-${calibSession}`}
        visible={calibOpen}
        connected={status === 'open'}
        gyroAvailable={preview ? true : air.gyroAvailable}
        motion={settings.motion}
        screenW={settings.screenW}
        screenH={settings.screenH}
        send={air.send}
        addGyroListener={air.addGyroListener}
        onFinish={finishCalibration}
        onClose={closeCalibration}
        onVerify={onVerify}
        hit={calibHit}
        preview={
          preview?.screen === 'calib' && preview.step
            ? { step: preview.step, progress: preview.progress, result: { biasX: 0.004, biasY: -0.002, biasZ: 0.003, sensitivity: 1642, sensitivityY: 1380 } }
            : undefined
        }
      />
    </View>
  );
}

export default function App() {
  return (
    <ErrorBoundary>
      <SafeAreaProvider>
        <TourProvider>
          <AirMouseApp />
        </TourProvider>
      </SafeAreaProvider>
    </ErrorBoundary>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
});
