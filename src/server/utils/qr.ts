import type { ErrorCorrection } from 'qr';
import { encodeQR } from 'qr';

export function encodeQRCode(config: string): string {
  return tryECCModes((ecc) => {
    return encodeQR(config, 'svg', {
      ecc,
      scale: 2,
      encoding: 'byte',
    });
  });
}

export function encodeQRCodeTerm(config: string): string {
  return tryECCModes((ecc) => {
    return encodeQR(config, 'term', {
      ecc,
      encoding: 'byte',
    });
  });
}

const ECC_PREFERENCE: readonly ErrorCorrection[] = [
  'high',
  'quartile',
  'medium',
  'low',
];

function tryECCModes<T>(callback: (ecc: ErrorCorrection) => T): T {
  for (const ecc of ECC_PREFERENCE) {
    try {
      return callback(ecc);
    } catch (err) {
      if (!(err instanceof Error && err.message === 'Capacity overflow')) {
        throw err;
      }
    }
  }
  throw new Error(
    'Failed to generate QR code: Capacity overflow at all ECC levels'
  );
}
