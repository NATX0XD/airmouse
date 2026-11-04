// Phone body size in millimetres (width x height, portrait), used by the Mac to
// draw the calibration outline at real size. Pure data, no React Native.

export type BodySize = { wMm: number; hMm: number };

export const FALLBACK_SIZE: BodySize = { wMm: 71.5, hMm: 147.5 };

// Keyed by Apple's internal model identifier (expo-device `modelId`).
const BY_MODEL_ID: Record<string, BodySize> = {
  'iPhone12,8': { wMm: 67.3, hMm: 138.4 }, // SE (2nd gen)
  'iPhone14,6': { wMm: 67.3, hMm: 138.4 }, // SE (3rd gen)
  'iPhone13,1': { wMm: 64.2, hMm: 131.5 }, // 12 mini
  'iPhone13,2': { wMm: 71.5, hMm: 146.7 }, // 12
  'iPhone13,3': { wMm: 71.5, hMm: 146.7 }, // 12 Pro
  'iPhone13,4': { wMm: 78.1, hMm: 160.8 }, // 12 Pro Max
  'iPhone14,4': { wMm: 64.2, hMm: 131.5 }, // 13 mini
  'iPhone14,5': { wMm: 71.5, hMm: 146.7 }, // 13
  'iPhone14,2': { wMm: 71.5, hMm: 146.7 }, // 13 Pro
  'iPhone14,3': { wMm: 78.1, hMm: 160.8 }, // 13 Pro Max
  'iPhone14,7': { wMm: 71.5, hMm: 146.7 }, // 14
  'iPhone14,8': { wMm: 78.1, hMm: 160.8 }, // 14 Plus
  'iPhone15,2': { wMm: 71.5, hMm: 147.5 }, // 14 Pro
  'iPhone15,3': { wMm: 77.6, hMm: 160.7 }, // 14 Pro Max
  'iPhone15,4': { wMm: 71.6, hMm: 147.6 }, // 15
  'iPhone15,5': { wMm: 77.8, hMm: 160.9 }, // 15 Plus
  'iPhone16,1': { wMm: 70.6, hMm: 146.6 }, // 15 Pro
  'iPhone16,2': { wMm: 76.7, hMm: 159.9 }, // 15 Pro Max
  'iPhone17,3': { wMm: 71.6, hMm: 147.6 }, // 16
  'iPhone17,4': { wMm: 77.8, hMm: 160.9 }, // 16 Plus
  'iPhone17,1': { wMm: 71.5, hMm: 149.6 }, // 16 Pro
  'iPhone17,2': { wMm: 77.6, hMm: 163.0 }, // 16 Pro Max
  'iPhone17,5': { wMm: 71.5, hMm: 146.7 }, // 16e
  'iPhone18,3': { wMm: 71.5, hMm: 149.6 }, // 17
  'iPhone18,1': { wMm: 71.9, hMm: 150.0 }, // 17 Pro
  'iPhone18,2': { wMm: 78.0, hMm: 163.4 }, // 17 Pro Max
  'iPhone18,4': { wMm: 74.7, hMm: 156.2 }, // Air
};

// Marketing names, for when only `modelName` is known (e.g. simulators).
const BY_NAME: Record<string, string> = {
  'iphone se (2nd generation)': 'iPhone12,8',
  'iphone se (3rd generation)': 'iPhone14,6',
  'iphone 12 mini': 'iPhone13,1',
  'iphone 12': 'iPhone13,2',
  'iphone 12 pro': 'iPhone13,3',
  'iphone 12 pro max': 'iPhone13,4',
  'iphone 13 mini': 'iPhone14,4',
  'iphone 13': 'iPhone14,5',
  'iphone 13 pro': 'iPhone14,2',
  'iphone 13 pro max': 'iPhone14,3',
  'iphone 14': 'iPhone14,7',
  'iphone 14 plus': 'iPhone14,8',
  'iphone 14 pro': 'iPhone15,2',
  'iphone 14 pro max': 'iPhone15,3',
  'iphone 15': 'iPhone15,4',
  'iphone 15 plus': 'iPhone15,5',
  'iphone 15 pro': 'iPhone16,1',
  'iphone 15 pro max': 'iPhone16,2',
  'iphone 16': 'iPhone17,3',
  'iphone 16 plus': 'iPhone17,4',
  'iphone 16 pro': 'iPhone17,1',
  'iphone 16 pro max': 'iPhone17,2',
  'iphone 16e': 'iPhone17,5',
  'iphone 17': 'iPhone18,3',
  'iphone 17 pro': 'iPhone18,1',
  'iphone 17 pro max': 'iPhone18,2',
  'iphone air': 'iPhone18,4',
};

export function bodySizeFor(modelId: string | null | undefined, modelName?: string | null): BodySize {
  if (modelId && BY_MODEL_ID[modelId]) return BY_MODEL_ID[modelId];
  const id = modelName ? BY_NAME[modelName.trim().toLowerCase()] : undefined;
  return id ? BY_MODEL_ID[id] : FALLBACK_SIZE;
}
