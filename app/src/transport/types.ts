// One message format for every way out of the phone (protocol v3, docs/spec-v3.md).
// WiFi sends these as JSON; the BLE dongle and Android HID paths encode the
// pointer messages as a 5-byte mouse report and drop the rest.

export type Button = 'left' | 'right';
// Calibration v3: centre, then the 4 corners inset 8 % (docs/spec-v3.md 4a).
export const CALIB_TARGET_IDS = ['center', 'tl', 'tr', 'br', 'bl'] as const;
export type CalibTarget = (typeof CALIB_TARGET_IDS)[number];

// Keys the phone can tap on the Mac. 'left'/'right' double as slide control.
export const KEY_NAMES = ['left', 'right', 'up', 'down', 'backspace', 'enter', 'tab', 'escape', 'space'] as const;
export type KeyName = (typeof KEY_NAMES)[number];

export type DeviceInfo = { name: string; model: string; wMm: number; hMm: number };

export type CalibMsg =
  | { t: 'calib'; step: 'start' }
  | { t: 'calib'; step: 'place'; progress: number; still: boolean; near?: boolean; upright?: boolean }
  | { t: 'calib'; step: 'placed' }
  | { t: 'calib'; step: 'point'; target: CalibTarget }
  | { t: 'calib'; step: 'pointed'; target: CalibTarget }
  | { t: 'calib'; step: 'verify' } // Mac shows the 5 dots and reports `hit` as the cursor touches them
  | { t: 'calib'; step: 'done'; sensitivity: number; sensitivityY?: number }
  | { t: 'calib'; step: 'cancel' };

export type Msg =
  | { t: 'move'; dx: number; dy: number }
  | { t: 'button'; b: Button; down: boolean }
  | { t: 'scroll'; dy: number } // positive = scroll down
  | { t: 'key'; k: KeyName } // arrows double as slide control
  | { t: 'text'; s: string } // type this text on the Mac
  | { t: 'center' }
  | { t: 'practice'; step: 'start' | 'stop' }
  | CalibMsg;

export type HelloMsg = { t: 'hello'; v: 3; app: 'airmouse'; device: DeviceInfo };

// Mac -> iPhone.
export type ScreenInfo = { w: number; h: number; scale?: number; wMm?: number; hMm?: number; name?: string };
export type InboundMsg =
  | ({ t: 'screen' } & ScreenInfo)
  | { t: 'calib'; step: 'request' }
  | { t: 'calib'; step: 'cancel' }
  | { t: 'calib'; step: 'hit'; target: CalibTarget }
  | { t: 'focus'; editable: boolean } // a text field gained / lost focus on the Mac
  | PracticeInbound;

export type PracticeInbound = { t: 'practice'; step: 'running' | 'result' | 'stop'; hits?: number; total?: number; ms?: number };

export type TransportStatus = 'idle' | 'connecting' | 'open' | 'error';

export interface Transport {
  readonly label: string;
  connect(): void;
  close(): void;
  // false = dropped (not open). void = transport doesn't know.
  send(msg: Msg): boolean | void;
  onStatus(cb: (s: TransportStatus, detail?: string) => void): () => void;
  onMessage?(cb: (m: InboundMsg) => void): () => void;
  // Settings > Diagnostics, transports that have something to say (Bluetooth).
  debugStats?(): Record<string, string | number>;
}
