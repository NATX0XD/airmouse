// Keep these values byte-for-byte identical to dongle/airmouse_dongle/uuids.h.
export const BLE_SERVICE_UUID = '7b0e0001-7d6b-4d9c-9a31-4a2d2f9e0101';
export const BLE_REPORT_CHARACTERISTIC_UUID = '7b0e0002-7d6b-4d9c-9a31-4a2d2f9e0101';
export const BLE_DEVICE_NAME = 'AirMouse-Dongle';

// AirMouse for Mac as a BLE peripheral (docs/spec-v3.md section 2b).
export const MAC_SERVICE_UUID = '7b0e0010-7d6b-4d9c-9a31-4a2d2f9e0101';
export const MAC_RX_UUID = '7b0e0011-7d6b-4d9c-9a31-4a2d2f9e0101'; // phone -> Mac, write
export const MAC_TX_UUID = '7b0e0012-7d6b-4d9c-9a31-4a2d2f9e0101'; // Mac -> phone, notify
export const MAC_NAME_PREFIX = 'AirMouse-';
