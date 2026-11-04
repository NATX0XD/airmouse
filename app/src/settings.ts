import AsyncStorage from '@react-native-async-storage/async-storage';
import { DEFAULT_SETTINGS, type MotionSettings } from './motion/engine';
import { migrateMotion, readCalibrated } from './setup/calibrated';
import { SETTINGS_KEY as KEY } from './setup/reset';

// 'hold' = cursor moves only while a finger is on the pad (clutch).
// 'always' = cursor always follows the phone; touch the pad to freeze it.
export type PointerMode = 'hold' | 'always';
// wifi = WebSocket to the Mac app, bluetooth = GATT to the Mac app,
// ble = ESP32 USB dongle (experimental), hid = Android Bluetooth HID (experimental).
export type TransportKind = 'wifi' | 'bluetooth' | 'ble' | 'hid';

export type AppSettings = {
  motion: MotionSettings;
  mode: PointerMode;
  host: string;
  port: number;
  transport: TransportKind;
  flickSlides: boolean;
  screenW: number;
  screenH: number;
  // v3 additions
  macName: string; // last Mac, for auto-connect and the status pill
  autoConnect: boolean;
  bleId: string; // last Bluetooth Mac (peripheral id)
  bleName: string;
  hasConnected: boolean; // a successful connection was made at least once
  screenWMm: number; // 0 = unknown
  screenHMm: number;
  screenName: string;
  calibratedAt: number; // epoch ms, 0 = never
  calibratedV3: string[];
  scrollNatural: boolean; // finger up = content scrolls down (like a trackpad)
  scrollSpeed: number; // 0.25 .. 3 // screenKey() of every display calibrated with the 5-point flow
};

export const DEFAULT_APP_SETTINGS: AppSettings = {
  motion: DEFAULT_SETTINGS,
  mode: 'hold',
  host: '',
  port: 8765,
  transport: 'wifi',
  flickSlides: true,
  screenW: 1920,
  screenH: 1080,
  macName: '',
  autoConnect: true,
  bleId: '',
  bleName: '',
  hasConnected: false,
  screenWMm: 0,
  screenHMm: 0,
  screenName: '',
  calibratedAt: 0,
  calibratedV3: [],
  scrollNatural: true,
  scrollSpeed: 1,
};


export async function loadSettings(): Promise<AppSettings> {
  try {
    const raw = await AsyncStorage.getItem(KEY);
    if (!raw) return DEFAULT_APP_SETTINGS;
    const saved = JSON.parse(raw) as Partial<AppSettings>;
    const s: AppSettings = { ...DEFAULT_APP_SETTINGS, ...saved, motion: migrateMotion(saved.motion) };
    s.calibratedV3 = readCalibrated(saved.calibratedV3);
    delete (s as Partial<{ calibratedScreens: unknown }>).calibratedScreens; // v3-beta list, dropped
    return s;
  } catch {
    return DEFAULT_APP_SETTINGS;
  }
}

export function saveSettings(s: AppSettings): void {
  AsyncStorage.setItem(KEY, JSON.stringify(s)).catch(() => {});
}
