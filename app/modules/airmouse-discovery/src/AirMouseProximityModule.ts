import { NativeModule, requireOptionalNativeModule } from 'expo';

type Events = {
  onProximityChange: (event: { near: boolean }) => void;
};

declare class AirMouseProximityModule extends NativeModule<Events> {
  // true = monitoring on; false = no proximity sensor (or turned off).
  setEnabled(enabled: boolean): Promise<boolean>;
  isNear(): Promise<boolean>;
}

// iOS-only. Optional lookup: null on Android/web or in a build without the
// native code, so nothing throws at import time.
export const AirMouseProximity = requireOptionalNativeModule<AirMouseProximityModule>('AirMouseProximity');
