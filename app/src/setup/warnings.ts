import type { PermissionId } from './steps';

export const WARNING_TEXT: Record<PermissionId, string> = {
  localNetwork: 'Local Network is off, so Wi-Fi can’t find your Mac.',
  bluetooth: 'Bluetooth is off for AirMouse.',
  camera: 'Camera is off, so QR codes can’t be scanned.',
  motion: 'Motion sensors aren’t available.',
};
