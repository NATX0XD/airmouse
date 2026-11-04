import { useEffect, useState } from 'react';
import { AirMouseDiscovery, type NearbyMac } from '../../modules/airmouse-discovery';

export type Nearby = { supported: boolean; macs: NearbyMac[]; error?: string };

// Several screens may browse at once (Setup + Connect): count users so one
// closing doesn't stop the other's browse.
let browseUsers = 0;
export function acquireBrowse(): () => void {
  const native = AirMouseDiscovery;
  if (!native) return () => {};
  if (browseUsers++ === 0) {
    try {
      native.start();
    } catch {
      /* reported through onBrowseError */
    }
  }
  let released = false;
  return () => {
    if (released) return;
    released = true;
    if (--browseUsers === 0) {
      try {
        native.stop();
      } catch {
        /* already stopped */
      }
    }
  };
}

// Bonjour browse for `_airmouse._tcp` while `active` (the Connect sheet is open).
export function useNearbyMacs(active: boolean): Nearby {
  const [macs, setMacs] = useState<NearbyMac[]>([]);
  const [error, setError] = useState<string | undefined>();
  const supported = AirMouseDiscovery !== null;

  useEffect(() => {
    const native = AirMouseDiscovery;
    if (!active || !native) return;
    const a = native.addListener('onServicesChanged', (e) => {
      setMacs(e.services ?? []);
      setError(undefined);
    });
    const b = native.addListener('onBrowseError', (e) => setError(e.message));
    const release = acquireBrowse();
    return () => {
      a.remove();
      b.remove();
      release();
      setMacs([]);
    };
  }, [active]);

  return { supported, macs, error };
}
