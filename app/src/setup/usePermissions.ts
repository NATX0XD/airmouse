import { useCallback, useEffect, useState } from 'react';
import { AppState, Linking, Platform } from 'react-native';
import { Camera } from 'expo-camera';
import { Gyroscope } from 'expo-sensors';
import { AirMouseDiscovery } from '../../modules/airmouse-discovery';
import { acquireBrowse } from '../connect/useNearbyMacs';
import { getBleManager } from '../transport/bleManager';
import { INITIAL_STATUSES, type PermissionId, type PermissionStatus, type Statuses } from './steps';

const POLL_MS = 1500;

async function check(): Promise<Statuses> {
  const out: Statuses = { ...INITIAL_STATUSES };
  const native = AirMouseDiscovery;
  try {
    out.localNetwork = native ? native.localNetworkState() : Platform.OS === 'android' ? 'granted' : 'unavailable';
  } catch {
    out.localNetwork = 'unknown';
  }
  try {
    const bt = native ? native.bluetoothAuthorization() : 'unknown';
    out.bluetooth = bt === 'restricted' ? 'denied' : bt;
  } catch {
    out.bluetooth = 'unknown';
  }
  try {
    const cam = await Camera.getCameraPermissionsAsync();
    out.camera = cam.granted ? 'granted' : cam.status === 'denied' || !cam.canAskAgain ? 'denied' : 'unknown';
  } catch {
    out.camera = 'unknown';
  }
  try {
    out.motion = (await Gyroscope.isAvailableAsync()) ? 'granted' : 'unavailable';
  } catch {
    out.motion = 'unavailable';
  }
  return out;
}

const same = (a: Statuses, b: Statuses) => (Object.keys(a) as PermissionId[]).every((k) => a[k] === b[k]);

// Live permission statuses. `polling` = re-check every 1.5 s (Setup visible).
export function usePermissions(polling: boolean) {
  const [statuses, setStatuses] = useState<Statuses>(INITIAL_STATUSES);

  const refresh = useCallback(() => {
    check()
      .then((s) => setStatuses((prev) => (same(prev, s) ? prev : s)))
      .catch(() => {});
  }, []);

  useEffect(() => {
    refresh();
    const app = AppState.addEventListener('change', (st) => st === 'active' && refresh());
    const native = AirMouseDiscovery;
    const ln = native?.addListener('onLocalNetworkState', (e) => setStatuses((prev) => (prev.localNetwork === e.state ? prev : { ...prev, localNetwork: e.state })));
    return () => {
      app.remove();
      ln?.remove();
    };
  }, [refresh]);

  useEffect(() => {
    if (!polling) return;
    const id = setInterval(refresh, POLL_MS);
    return () => clearInterval(id);
  }, [polling, refresh]);

  // While the Setup is open, keep a Bonjour browse running: it triggers the
  // Local Network prompt and is how its answer is detected.
  useEffect(() => {
    if (!polling) return;
    return acquireBrowse();
  }, [polling]);

  const request = useCallback(
    async (id: PermissionId, status: PermissionStatus) => {
      if (status === 'denied') {
        await Linking.openSettings().catch(() => {});
        return;
      }
      try {
        if (id === 'localNetwork') {
          const release = acquireBrowse(); // shows the prompt on first use
          setTimeout(release, 8000);
        } else if (id === 'bluetooth') {
          getBleManager(); // creating CoreBluetooth shows the prompt
        } else if (id === 'camera') {
          await Camera.requestCameraPermissionsAsync();
        }
      } finally {
        setTimeout(refresh, 300);
      }
    },
    [refresh],
  );

  return { statuses, refresh, request };
}
