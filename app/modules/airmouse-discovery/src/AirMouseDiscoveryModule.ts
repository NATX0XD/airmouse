import { NativeModule, requireOptionalNativeModule } from 'expo';

export type NearbyMac = { name: string; host?: string; port?: number };

type Events = {
  onServicesChanged: (event: { services: NearbyMac[] }) => void;
  onBrowseError: (event: { message: string }) => void;
  onLocalNetworkState: (event: { state: LocalNetworkState }) => void;
};

export type LocalNetworkState = 'unknown' | 'granted' | 'denied';
export type BluetoothAuthorization = 'unknown' | 'granted' | 'denied' | 'restricted';

declare class AirMouseDiscoveryModule extends NativeModule<Events> {
  start(): void;
  stop(): void;
  localNetworkState(): LocalNetworkState;
  bluetoothAuthorization(): BluetoothAuthorization;
}

// iOS-only module. Optional lookup: null on Android/web or in a build without
// the native code, so nothing throws at import time.
export const AirMouseDiscovery = requireOptionalNativeModule<AirMouseDiscoveryModule>('AirMouseDiscovery');
export default AirMouseDiscovery;
