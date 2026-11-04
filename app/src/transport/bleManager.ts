import { BleManager } from 'react-native-ble-plx';

// One BleManager for the whole app, created on first use, never at import:
// constructing it starts CoreBluetooth and shows the Bluetooth permission
// prompt, which should only happen once the user picks a Bluetooth option.
let shared: BleManager | null = null;
export const getBleManager = () => (shared ??= new BleManager());
