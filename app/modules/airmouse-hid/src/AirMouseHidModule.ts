import { NativeModule, requireOptionalNativeModule } from 'expo';
import type { EventSubscription } from 'expo-modules-core';

export type BondedDevice = { address: string; name: string | null };
declare class AirMouseHidModule extends NativeModule<{ onStateChange: (event: { address: string; state: number }) => void }> {
  isSupported(): boolean;
  register(): Promise<void>;
  getBondedDevices(): BondedDevice[];
  connect(address: string): Promise<void>;
  disconnect(): Promise<void>;
  send(report: number[]): Promise<boolean>;
}

// Android-only module. requireNativeModule would throw on iOS at import time and
// leave the whole app on a black screen, so look it up optionally: null = not available.
export const AirMouseHid = requireOptionalNativeModule<AirMouseHidModule>('AirMouseHid');
export default AirMouseHid;
