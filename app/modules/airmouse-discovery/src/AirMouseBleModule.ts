import { NativeModule, requireOptionalNativeModule } from 'expo';

type Events = {
  onBleStatus: (e: { status: 'connecting' | 'open' | 'closed' | 'error'; detail?: string; id?: string }) => void;
  onBleMessage: (e: { text: string }) => void;
};

export type NativeBleStats = { open: boolean; writes: number; moves: number; merged: number; waits: number; queued: number; maxWrite: number; lastError: string };

declare class AirMouseBleModule extends NativeModule<Events> {
  connect(id: string, name: string): void;
  disconnect(): void;
  send(text: string): void;
  sendMove(dx: number, dy: number): void;
  stats(): NativeBleStats;
}

// iOS native BLE central for the Mac (write without response, native move
// coalescing). null elsewhere: callers fall back to the ble-plx transport.
export const AirMouseBle = requireOptionalNativeModule<AirMouseBleModule>('AirMouseBle');
